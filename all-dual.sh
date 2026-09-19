#!/bin/bash
#################################################################################
# Run script for lazycast - Dual Display Mode
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
BASE_DIR="$(pwd)"

source ./lib-p2p.sh

# Carregar configurações
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
else
    echo "Arquivo de configuração não encontrado. Execute ./install.sh primeiro."
    exit 1
fi

# Verificar modo de display
if [ "$DISPLAY_MODE" != "2" ]; then
    echo "Modo dual display não configurado. Execute ./install.sh para configurar."
    exit 1
fi

# [RPi5/dual] Cada instância precisa de porta RTP própria e de uma tela própria.
# Antes as duas usavam a porta 1028 e o 'pkill vlc' de uma matava o player da outra.
DISPLAY1_RTP_PORT=${DISPLAY1_RTP_PORT:-1028}
DISPLAY2_RTP_PORT=${DISPLAY2_RTP_PORT:-1030}
DISPLAY1_SCREEN=${DISPLAY1_SCREEN:-0}
DISPLAY2_SCREEN=${DISPLAY2_SCREEN:-1}

LD_LIBRARY_PATH=/opt/vc/lib
export LD_LIBRARY_PATH

echo "=========================================="
echo "  LazyCast Dual Display Mode"
echo "=========================================="
echo "Display 1: $DISPLAY1_NAME ($DISPLAY1_IP) tela=$DISPLAY1_SCREEN rtp=$DISPLAY1_RTP_PORT"
echo "Display 2: $DISPLAY2_NAME ($DISPLAY2_IP) tela=$DISPLAY2_SCREEN rtp=$DISPLAY2_RTP_PORT"
echo "=========================================="
echo ""

list_p2p_devs() {
    sudo wpa_cli interface 2>/dev/null | grep -E "^p2p-dev-"
}

pause_networkmanager
cleanup_orphan_p2p_ifaces

# Limpar informações de pareamento antigas em todas as interfaces p2p-dev
# (antes: apenas p2p-dev-wlan0 fixo)
echo 'Limpando informações de pareamento antigas...'
for dev in $(list_p2p_devs); do
    sudo wpa_cli -i "$dev" remove_network all >/dev/null 2>&1 || true
done

# [RPi5/dual] O chip Wi-Fi interno do Pi só sustenta UM grupo P2P por vez. Para dois
# displays realmente independentes é preciso um segundo adaptador Wi-Fi (USB) com
# p2p-dev próprio; cada instância usa a N-ésima interface p2p-dev. Sem a segunda,
# o Display 2 fica aguardando (antes: o Display 2 sobrescrevia o IP/nome do Display 1).
for _ in $(seq 1 10); do
    P2P_DEV_COUNT=$(list_p2p_devs | wc -l)
    [ "$P2P_DEV_COUNT" -ge 1 ] && break
    sleep 2
done
if [ "$P2P_DEV_COUNT" -lt 2 ]; then
    echo "AVISO: apenas $P2P_DEV_COUNT interface(s) Wi-Fi P2P (p2p-dev-*) encontrada(s)."
    echo "       O Display 2 só iniciará quando houver um segundo adaptador Wi-Fi com suporte a P2P."
fi

# Função para iniciar uma instância do LazyCast
start_display_instance() {
    local display_name=$1
    local display_ip=$2
    local dhcp_start=$3
    local dhcp_end=$4
    local sound_output=$5
    local player_select=$6
    local interface_suffix=$7
    local rtp_port=$8
    local screen=$9
    local dev_index=${10}
    local p2p_dev_pin=${11}
    local vlc_args=${12}

    echo "Iniciando instância para $display_name..." >&2

    # Criar diretório temporário para esta instância
    local instance_dir="$BASE_DIR/lazycast_instance_$interface_suffix"
    mkdir -p "$instance_dir/control"
    cd "$instance_dir" || return 1

    # Copiar arquivos necessários (d2.py espera os binários em ./control)
    cp "$BASE_DIR/d2.py" .
    cp "$BASE_DIR/control/control.bin" control/ 2>/dev/null || true
    cp "$BASE_DIR/control/controlhidc.bin" control/ 2>/dev/null || true

    # Modificar configurações no d2.py
    sed -i "s/^player_select = .*/player_select = $player_select/" d2.py
    sed -i "s/^sound_output_select = .*/sound_output_select = $sound_output/" d2.py

    # Criar log específico (caminho relativo ao diretório da instância)
    local log_file="lazycast_$interface_suffix.log"

    # Iniciar processo em background
    (
        warned_nodev=0
        while :
        do
            # [RPi5/dual] N-ésima interface p2p-dev para a N-ésima instância
            # DISPLAYn_P2P_DEV fixa o adaptador (ordem de enumeração não é estável); senão usa o N-ésimo
            if [ -n "$p2p_dev_pin" ]; then
                p2pdevinterface=$(list_p2p_devs | grep -Fx "$p2p_dev_pin")
            else
                p2pdevinterface=$(list_p2p_devs | sed -n "${dev_index}p")
            fi
            wlaninterface=${p2pdevinterface#p2p-dev-}

            if [ -z "$p2pdevinterface" ]; then
                if [ "$warned_nodev" = "0" ]; then
                    echo "Interface P2P #$dev_index não encontrada (é necessário um adaptador Wi-Fi por display). Aguardando..."
                    warned_nodev=1
                fi
                sleep 5
                continue
            fi
            warned_nodev=0

            ain="$(sudo wpa_cli interface)"
            group_re="^p2p-${wlaninterface}-[0-9]+"

            if [ `echo "${ain}" | grep -cE "$group_re"` -gt 0 ]; then
                echo "Interface P2P já ativa"
            else
                # Configurar dispositivo P2P com nome específico
                sudo wpa_cli -i"$p2pdevinterface" p2p_find type=progressive
                sudo wpa_cli -i"$p2pdevinterface" set device_name "$display_name"
                sudo wpa_cli -i"$p2pdevinterface" set device_type 7-0050F204-1
                sudo wpa_cli -i"$p2pdevinterface" set p2p_go_ht40 1
                sudo wpa_cli -i"$p2pdevinterface" wfd_subelem_set 0 000600111c44012c
                sudo wpa_cli -i"$p2pdevinterface" wfd_subelem_set 1 0006000000000000
                sudo wpa_cli -i"$p2pdevinterface" wfd_subelem_set 6 000700000000000000

                perentry="$(sudo wpa_cli -i"$p2pdevinterface" list_networks | grep "\[DISABLED\]\[P2P-PERSISTENT\]" | tail -1)"

                if [ `echo "${perentry}" | grep -c "P2P-PERSISTENT"`  -gt 0 ]; then
                    networkid=${perentry%%D*}
                    perstr="=${networkid}"
                else
                    perstr=""
                fi

                while [ `echo "${ain}" | grep -cE "$group_re"` -lt 1 ]; do
                    result=$(sudo wpa_cli p2p_group_add -i"$p2pdevinterface" persistent$perstr)
                    if [ "$result" == "FAIL" ]; then
                        echo "p2p_group_add falhou (FAIL); limpando interfaces P2P órfãs"
                        cleanup_orphan_p2p_ifaces
                        # persistent inválido: tenta de novo sem ele
                        perstr=""
                    fi
                    sleep 2
                    ain="$(sudo wpa_cli interface)"
                    if [ `echo "${ain}" | grep -cE "$group_re"` -lt 1 ]; then
                        sleep 5
                        ain="$(sudo wpa_cli interface)"
                    fi
                done
            fi

            p2pinterface=$(echo "${ain}" | grep -E "$group_re" | grep -v "interface" | head -1)

            if [ -z "$p2pinterface" ]; then
                echo "Interface P2P não encontrada após criação"
                sleep 5
                continue
            fi

            # Configurar interface com IP específico
            sudo ifconfig "$p2pinterface" "$display_ip"

            # Criar configuração DHCP específica
            # [fix] lease_file próprio: as duas instâncias dividiam o mesmo arquivo de leases
            cat > "udhcpd_$interface_suffix.conf" << EOF
start	$dhcp_start
end	$dhcp_end
interface	$p2pinterface
option subnet 255.255.255.0
option lease 10000
lease_file	$instance_dir/udhcpd_$interface_suffix.leases
EOF

            sleep 3
            # [fix] encerra udhcpd anterior desta instância antes de subir outro (evita duplicados)
            sudo pkill -f "[u]dhcpd ./udhcpd_$interface_suffix.conf" 2>/dev/null
            sudo busybox udhcpd "./udhcpd_$interface_suffix.conf"

            echo "The display is ready"
            echo "Display $display_name está pronto"
            echo "Seu dispositivo é chamado: $display_name"

            while :
            do
                # Executar d2.py com configuração específica desta instância
                env DISPLAY="${DISPLAY:-:0}" \
                    LAZYCAST_RTP_PORT="$rtp_port" \
                    LAZYCAST_SCREEN="$screen" \
                    LAZYCAST_VLC_ARGS="$vlc_args" \
                    LAZYCAST_NAME="$display_name" \
                    ./d2.py "$dhcp_start"

                if [ `sudo wpa_cli interface | grep -cE "$group_re"` == 0 ]; then
                    break
                fi

                sleep 1
            done
        done
    ) > "$log_file" 2>&1 &

    local pid=$!
    echo "Instância $display_name iniciada (PID: $pid)" >&2
    echo "Log: $instance_dir/$log_file" >&2

    cd "$BASE_DIR"
    # Somente o PID vai para stdout, pois o chamador captura a saída com $(...)
    echo $pid
}

cleanup() {
    echo "Parando displays..."
    resume_networkmanager
    kill $display1_pid $display2_pid 2>/dev/null
    # [fix] o kill acima só atinge o subshell; encerra também os filhos (d2.py, vlc, udhcpd)
    pkill -f "[d]2.py $DISPLAY1_DHCP_START" 2>/dev/null
    pkill -f "[d]2.py $DISPLAY2_DHCP_START" 2>/dev/null
    pkill -f "rtp://0.0.0.0:$DISPLAY1_RTP_PORT" 2>/dev/null
    pkill -f "rtp://0.0.0.0:$DISPLAY2_RTP_PORT" 2>/dev/null
    sudo pkill -f "[u]dhcpd ./udhcpd_display" 2>/dev/null
    exit 0
}

# Iniciar Display 1
echo "Iniciando Display 1..."
display1_pid=$(start_display_instance "$DISPLAY1_NAME" "$DISPLAY1_IP" "$DISPLAY1_DHCP_START" "$DISPLAY1_DHCP_END" "$DISPLAY1_SOUND_OUTPUT" "$DISPLAY1_PLAYER_SELECT" "display1" "$DISPLAY1_RTP_PORT" "$DISPLAY1_SCREEN" 1 "$DISPLAY1_P2P_DEV" "$DISPLAY1_VLC_ARGS")

# Aguardar um pouco antes de iniciar o segundo display
sleep 3

# Iniciar Display 2
echo "Iniciando Display 2..."
display2_pid=$(start_display_instance "$DISPLAY2_NAME" "$DISPLAY2_IP" "$DISPLAY2_DHCP_START" "$DISPLAY2_DHCP_END" "$DISPLAY2_SOUND_OUTPUT" "$DISPLAY2_PLAYER_SELECT" "display2" "$DISPLAY2_RTP_PORT" "$DISPLAY2_SCREEN" 2 "$DISPLAY2_P2P_DEV" "$DISPLAY2_VLC_ARGS")

echo ""
echo "=========================================="
echo "  Ambos os displays estão ativos"
echo "=========================================="
echo "Display 1 PID: $display1_pid"
echo "Display 2 PID: $display2_pid"
echo ""
echo "Para parar os displays, pressione Ctrl+C"
echo ""

# Aguardar sinais de interrupção
trap cleanup INT TERM

while true; do
    sleep 10

    # Verificar se os processos ainda estão rodando
    if ! kill -0 $display1_pid 2>/dev/null; then
        echo "Display 1 parou inesperadamente"
        display1_pid=$(start_display_instance "$DISPLAY1_NAME" "$DISPLAY1_IP" "$DISPLAY1_DHCP_START" "$DISPLAY1_DHCP_END" "$DISPLAY1_SOUND_OUTPUT" "$DISPLAY1_PLAYER_SELECT" "display1" "$DISPLAY1_RTP_PORT" "$DISPLAY1_SCREEN" 1 "$DISPLAY1_P2P_DEV" "$DISPLAY1_VLC_ARGS")
    fi

    if ! kill -0 $display2_pid 2>/dev/null; then
        echo "Display 2 parou inesperadamente"
        display2_pid=$(start_display_instance "$DISPLAY2_NAME" "$DISPLAY2_IP" "$DISPLAY2_DHCP_START" "$DISPLAY2_DHCP_END" "$DISPLAY2_SOUND_OUTPUT" "$DISPLAY2_PLAYER_SELECT" "display2" "$DISPLAY2_RTP_PORT" "$DISPLAY2_SCREEN" 2 "$DISPLAY2_P2P_DEV" "$DISPLAY2_VLC_ARGS")
    fi
done
