#!/bin/bash
#################################################################################
# Run script for lazycast
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#   You may copy, distribute and modify the software as long as you track
#   changes/dates in source files. Any modifications to our software
#   including (via compiler) GPL-licensed code must also be made available
#   under the GPL along with build & install instructions.
#
#################################################################################
# O serviço/cron pode chamar este script de outro diretório
cd "$(dirname "$0")" || exit 1

source ./lib-p2p.sh

# Carregar configurações se disponíveis
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
    managefrequency=$MANAGE_FREQUENCY
    display_name=$DISPLAY1_NAME
    display_ip=$DISPLAY1_IP
    dhcp_start=$DISPLAY1_DHCP_START
    dhcp_end=$DISPLAY1_DHCP_END
    sound_output=$DISPLAY1_SOUND_OUTPUT
    player_select=$DISPLAY1_PLAYER_SELECT
else
    # Configurações padrão
    managefrequency=0
    display_name=$(uname -n)
    display_ip="192.168.173.1"
    dhcp_start="192.168.173.80"
    dhcp_end="192.168.173.80"
    sound_output=2
    player_select=2
fi

# [dual/1 adaptador] SHARED_SLOTS=2: UM grupo P2P (o Wi-Fi interno só sustenta um) e DUAS fontes
# entram nele; cada fonte recebe um IP (.80, .81) e uma instância do receptor com porta RTP e
# tela próprias. A 1ª fonte que conectar vai para o Display 1 e a 2ª para o Display 2.
slots=${SHARED_SLOTS:-1}
[ "$slots" -gt 2 ] && slots=2   # 1 ou 2 telas
# Telas sem fio (índices 0-based); as de fonte usb:/stream: (SCREENn_SOURCE) não usam o Wi-Fi Direct
wl=($(wireless_screens "$slots"))
nwl=${#wl[@]}
wl_ip() { echo "${dhcp_start%.*}.$(( ${dhcp_start##*.} + $1 ))"; }   # IP da j-ésima tela sem fio (0-based)
if [ "$nwl" -ge 1 ]; then dhcp_end="$(wl_ip $(( nwl - 1 )))"; fi

LD_LIBRARY_PATH=/opt/vc/lib
export LD_LIBRARY_PATH
echo 'Limpando informações de pareamento antigas...'
# [fix] antes: p2p-dev-wlan0 fixo; agora todas as interfaces p2p-dev existentes
for dev in $(sudo wpa_cli interface 2>/dev/null | grep -E "^p2p-dev-"); do
	sudo wpa_cli -i "$dev" remove_network all >/dev/null 2>&1 || true
done

pause_networkmanager
cleanup_orphan_p2p_ifaces
slot_pids=()
stop_slots() {
    local j
    [ "${#slot_pids[@]}" -gt 0 ] && kill "${slot_pids[@]}" 2>/dev/null
    pkill -f "[w]ired-input.sh" 2>/dev/null
    for ((j = 1; j < nwl; j++)); do pkill -f "[d]2.py $(wl_ip $j)" 2>/dev/null; done
}
trap 'stop_slots; resume_networkmanager; exit 0' INT TERM HUP

while :
do
	# [usb] por capacidade (não pelo nome): DISPLAY1_P2P_DEV fixa o adaptador (nome ou MAC)
	if [ -n "$DISPLAY1_P2P_DEV" ]; then
		p2pdevinterface=$(resolve_p2p_dev_pin "$DISPLAY1_P2P_DEV")
	else
		p2pdevinterface=$(list_p2p_devs | head -1)
	fi
	wlaninterface=${p2pdevinterface#p2p-dev-}
	echo $p2pdevinterface
	echo $wlaninterface
	ain="$(sudo wpa_cli interface)"
	echo "${ain}"
	if [ `echo "${ain}" | grep -c "p2p-wl"` -gt 0 ] 
	then
		echo "already on"

	else
		sudo wpa_cli -i$p2pdevinterface p2p_find type=progressive
		sudo wpa_cli -i$p2pdevinterface set device_name "$display_name"
		set_p2p_network_name "$p2pdevinterface" "$display_name"
		sudo wpa_cli -i$p2pdevinterface set device_type 7-0050F204-1
		set_wps_config_methods "$p2pdevinterface"
		sudo wpa_cli -i$p2pdevinterface set p2p_go_ht40 1
		# [RPi5] Sem wifi_display=1 o wpa_supplicant NÃO inclui o IE WFD nas respostas (log: "Wi-Fi Display
		# disabled - do not include WFD IE") e o Windows/Android nunca listam o receptor.
		sudo wpa_cli -i$p2pdevinterface set wifi_display 1
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 0 000600111c44012c
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 1 0006000000000000
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 6 000700000000000000
		perentry="$(sudo wpa_cli -i$p2pdevinterface list_networks | grep "\[DISABLED\]\[P2P-PERSISTENT\]" | tail -1)"
		echo "${perentry}"
		if [ `echo "${perentry}" | grep -c "P2P-PERSISTENT"`  -gt 0 ] 
		then
			networkid=${perentry%%D*}
			perstr="=${networkid}"
		else
			perstr=""
		fi
		echo "${perstr}"
		echo "${p2pdevinterface}"
		wlanfreq=$(sudo wpa_cli -i$wlaninterface status | grep "freq")
		if [ "$managefrequency" == "0" ]
		then
			wlanfreq=""
		fi
		if [ "$wlanfreq" != "" ]
		then	
			echo $wlaninterface": "$wlanfreq
			echo "Setting up wifi p2p with "$wlanfreq
		fi
		while [ `echo "${ain}" | grep -c "p2p-wl"`  -lt 1 ] 
		do
			while [ `echo "${ain}" | grep -c "p2p-wl"`  -lt 1 ]
			do
				#sudo wpa_cli p2p_group_add -i$p2pdevinterface persistent$perstr freq=2
				result=$(sudo wpa_cli p2p_group_add -i$p2pdevinterface persistent$perstr)
				if [ "$result" == "FAIL" ]					
				then
					echo "p2p_group_add falhou (FAIL); limpando interfaces P2P órfãs e tentando de novo"
					cleanup_orphan_p2p_ifaces
					wlanfreq=""
					managefrequency=0
				fi
				sleep 2
				ain="$(sudo wpa_cli interface)"
				echo "$ain"
			done
			sleep 5
			ain="$(sudo wpa_cli interface)"
		    echo "$ain"
		done

	fi

	p2pinterface=$(echo "${ain}" | grep "p2p-wl" | grep -v "interface")
	echo $p2pinterface

	sudo ifconfig $p2pinterface $display_ip
	register_wps_auth "$p2pinterface"
	printf "start	$dhcp_start\n">udhcpd.conf
	printf "end	$dhcp_end\n">>udhcpd.conf
	printf "interface	$p2pinterface\n">>udhcpd.conf
	printf "option subnet 255.255.255.0\n">>udhcpd.conf
	# [fix] pool de 1 endereço: leases limpos ao criar o grupo e liberados ao desconectar (watch_dhcp_release)
	printf "option lease 10000\n">>udhcpd.conf
	printf "lease_file $PWD/udhcpd.leases\n">>udhcpd.conf
	rm -f "$PWD/udhcpd.leases"
	sleep 3
	# [fix] evita udhcpd duplicado a cada reconexão
	sudo pkill -f "[u]dhcpd ./udhcpd.conf" 2>/dev/null
	sudo busybox udhcpd ./udhcpd.conf
	watch_dhcp_release "$p2pinterface" ./udhcpd.conf "$PWD/udhcpd.leases" &
	echo "The display is ready"
	echo "Your device is called: $display_name"
	slot_pids=()
	setup_vlc_output "$slots"
	# Entradas COM FIO (capturadora USB ou fluxo de rede): um laço por tela com fonte usb:/stream:
	for ((k = 0; k < slots; k++)); do
		src="$(screen_source $k)"
		if is_wired_source "$src"; then
			echo "  Tela $((k + 1)) = entrada com fio ($src)"
			./wired-input.sh "$k" "$src" >/dev/null 2>&1 &
			slot_pids+=($!)
		fi
	done
	# Telas sem fio a partir da 2ª (a 1ª, wl[0], roda em primeiro plano mais abaixo)
	for ((j = 1; j < nwl; j++)); do
		k=${wl[$j]}; ip_s=$(wl_ip $j); rtp_s=$(screen_rtp $k)
		echo "  Tela $((k + 1)) = sem fio em $ip_s (porta RTP $rtp_s)"
		(
			while [ -d "/sys/class/net/$p2pinterface" ]
			do
				LAZYCAST_NAME="$display_name" LAZYCAST_RTP_PORT="$rtp_s" LAZYCAST_SCREEN="$k" LAZYCAST_VLC_ARGS="$(screen_vlc_args $k)" ./d2.py "$ip_s"
				sleep 1
			done
		) &
		slot_pids+=($!)
	done
	if [ "$nwl" -ge 1 ]; then
		fg_screen=${wl[0]}; fg_rtp=$(screen_rtp "$fg_screen"); fg_vlc_args="$(screen_vlc_args "$fg_screen")"
		echo "  Tela $((fg_screen + 1)) = sem fio em $dhcp_start (porta RTP $fg_rtp)"
	fi
	while :
	do	
		# Modificar configurações do d2.py dinamicamente
		if [ -f d2.py ]; then
			sed -i "s/^player_select = .*/player_select = $player_select/" d2.py
			sed -i "s/^sound_output_select = .*/sound_output_select = $sound_output/" d2.py
		fi
		# [fix] d2.py anuncia o nome configurado (antes: 'raspberrypi' fixo)
		if [ "$nwl" -ge 1 ]; then
			LAZYCAST_NAME="$display_name" LAZYCAST_RTP_PORT="$fg_rtp" LAZYCAST_SCREEN="$fg_screen" LAZYCAST_VLC_ARGS="$fg_vlc_args" ./d2.py "$dhcp_start"
		else
			sleep 3   # todas as telas são com fio: nada a receber pelo Wi-Fi Direct
		fi
		if [ `sudo wpa_cli interface | grep -c "p2p-wl"` == 0 ] 
		then
			break
		fi
		
		wlanfreq=$(sudo wpa_cli -i$wlaninterface status | grep "freq")
		p2pfreq=$(sudo wpa_cli -i$p2pinterface status | grep "freq")
		if [ "$managefrequency" == "0" ]
		then
			wlanfreq=""
		fi
		if [ "$wlanfreq" != "" ]
		then		
			if [ "$wlanfreq" != "$p2pfreq" ] 
			then
				echo "The display is disconnected since "$wlaninterface" changes from "$p2pfreq" to "$wlanfreq
				echo "To disable WLAN roaming, run: sudo killall -STOP NetworkManager"
				echo "You can re-enable roaming afterwards by running: sudo killall -CONT NetworkManager"
				sudo wpa_cli -i$p2pinterface p2p_group_remove $p2pinterface
				while :
				do
					if [ `sudo wpa_cli interface | grep -c "p2p-wl"` == 0 ] 
					then
						break
					fi
					sleep 0.5  # [perf] antes: laço ocupado a 100% de CPU
				done
				break
			fi
		fi

	done
done
