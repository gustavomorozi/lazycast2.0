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

LD_LIBRARY_PATH=/opt/vc/lib
export LD_LIBRARY_PATH

echo "=========================================="
echo "  LazyCast Dual Display Mode"
echo "=========================================="
echo "Display 1: $DISPLAY1_NAME ($DISPLAY1_IP)"
echo "Display 2: $DISPLAY2_NAME ($DISPLAY2_IP)"
echo "=========================================="
echo ""

# Limpar informações de pareamento antigas
echo 'Limpando informações de pareamento antigas...'
sudo wpa_cli -i p2p-dev-wlan0 remove_network all 2>/dev/null || true

# Função para iniciar uma instância do LazyCast
start_display_instance() {
    local display_name=$1
    local display_ip=$2
    local dhcp_start=$3
    local dhcp_end=$4
    local sound_output=$5
    local player_select=$6
    local interface_suffix=$7
    
    echo "Iniciando instância para $display_name..."
    
    # Criar diretório temporário para esta instância
    local instance_dir="lazycast_instance_$interface_suffix"
    mkdir -p "$instance_dir"
    cd "$instance_dir"
    
    # Copiar arquivos necessários
    cp ../d2.py .
    cp ../player/player.bin . 2>/dev/null || true
    cp ../h264/h264.bin . 2>/dev/null || true
    cp ../control/control.bin . 2>/dev/null || true
    cp ../control/controlhidc.bin . 2>/dev/null || true
    
    # Modificar configurações no d2.py
    sed -i "s/^player_select = .*/player_select = $player_select/" d2.py
    sed -i "s/^sound_output_select = .*/sound_output_select = $sound_output/" d2.py
    
    # Criar log específico
    local log_file="$instance_dir/lazycast_$interface_suffix.log"
    
    # Iniciar processo em background
    (
        while :
        do
            p2pdevinterface=$(sudo wpa_cli interface | grep -E "p2p-dev" | tail -1)
            wlaninterface=$(echo $p2pdevinterface | cut -c1-8 --complement)
            
            if [ -z "$p2pdevinterface" ]; then
                echo "Interface P2P não encontrada. Aguardando..."
                sleep 5
                continue
            fi
            
            ain="$(sudo wpa_cli interface)"
            
            if [ `echo "${ain}" | grep -c "p2p-wl"` -gt 0 ]; then
                echo "Interface P2P já ativa"
            else
                # Configurar dispositivo P2P com nome específico
                sudo wpa_cli -i$p2pdevinterface p2p_find type=progressive
                sudo wpa_cli -i$p2pdevinterface set device_name "$display_name"
                sudo wpa_cli -i$p2pdevinterface set device_type 7-0050F204-1
                sudo wpa_cli -i$p2pdevinterface set p2p_go_ht40 1
                sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 0 000600111c44012c
                sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 1 0006000000000000
                sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 6 000700000000000000
                
                perentry="$(sudo wpa_cli -i$p2pdevinterface list_networks | grep "\[DISABLED\]\[P2P-PERSISTENT\]" | tail -1)"
                
                if [ `echo "${perentry}" | grep -c "P2P-PERSISTENT"`  -gt 0 ]; then
                    networkid=${perentry%%D*}
                    perstr="=${networkid}"
                else
                    perstr=""
                fi
                
                wlanfreq=$(sudo wpa_cli -i$wlaninterface status | grep "freq")
                if [ "$MANAGE_FREQUENCY" == "0" ]; then
                    wlanfreq=""
                fi
                
                while [ `echo "${ain}" | grep -c "p2p-wl"`  -lt 1 ]; do
                    while [ `echo "${ain}" | grep -c "p2p-wl"`  -lt 1 ]; do
                        result=$(sudo wpa_cli p2p_group_add -i$p2pdevinterface persistent$perstr)
                        if [ "$result" == "FAIL" ]; then
                            wlanfreq=""
                        fi
                        sleep 2
                        ain="$(sudo wpa_cli interface)"
                    done
                    sleep 5
                    ain="$(sudo wpa_cli interface)"
                done
            fi
            
            p2pinterface=$(echo "${ain}" | grep "p2p-wl" | grep -v "interface")
            
            if [ -z "$p2pinterface" ]; then
                echo "Interface P2P não encontrada após criação"
                sleep 5
                continue
            fi
            
            # Configurar interface com IP específico
            sudo ifconfig $p2pinterface $display_ip
            
            # Criar configuração DHCP específica
            printf "start\t$dhcp_start\n">udhcpd_$interface_suffix.conf
            printf "end\t$dhcp_end\n">>udhcpd_$interface_suffix.conf
            printf "interface\t$p2pinterface\n">>udhcpd_$interface_suffix.conf
            printf "option subnet 255.255.255.0\n">>udhcpd_$interface_suffix.conf
            printf "option lease 10000">>udhcpd_$interface_suffix.conf
            
            sleep 3
            sudo busybox udhcpd ./udhcpd_$interface_suffix.conf 
            
            echo "Display $display_name está pronto"
            echo "Seu dispositivo é chamado: $display_name"
            
            while :
            do    
                # Executar d2.py com configuração específica
                DISPLAY=:0 ./d2.py $dhcp_start
                
                if [ `sudo wpa_cli interface | grep -c "p2p-wl"` == 0 ]; then
                    break
                fi
                
                sleep 1
            done
        done
    ) > "$log_file" 2>&1 &
    
    local pid=$!
    echo "Instância $display_name iniciada (PID: $pid)"
    echo "Log: $log_file"
    
    cd ..
    echo $pid
}

# Iniciar Display 1
echo "Iniciando Display 1..."
display1_pid=$(start_display_instance "$DISPLAY1_NAME" "$DISPLAY1_IP" "$DISPLAY1_DHCP_START" "$DISPLAY1_DHCP_END" "$DISPLAY1_SOUND_OUTPUT" "$DISPLAY1_PLAYER_SELECT" "display1")

# Aguardar um pouco antes de iniciar o segundo display
sleep 3

# Iniciar Display 2
echo "Iniciando Display 2..."
display2_pid=$(start_display_instance "$DISPLAY2_NAME" "$DISPLAY2_IP" "$DISPLAY2_DHCP_START" "$DISPLAY2_DHCP_END" "$DISPLAY2_SOUND_OUTPUT" "$DISPLAY2_PLAYER_SELECT" "display2")

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
trap "echo 'Parando displays...'; kill $display1_pid $display2_pid 2>/dev/null; exit 0" INT TERM

while true; do
    sleep 10
    
    # Verificar se os processos ainda estão rodando
    if ! kill -0 $display1_pid 2>/dev/null; then
        echo "Display 1 parou inesperadamente"
        display1_pid=$(start_display_instance "$DISPLAY1_NAME" "$DISPLAY1_IP" "$DISPLAY1_DHCP_START" "$DISPLAY1_DHCP_END" "$DISPLAY1_SOUND_OUTPUT" "$DISPLAY1_PLAYER_SELECT" "display1")
    fi
    
    if ! kill -0 $display2_pid 2>/dev/null; then
        echo "Display 2 parou inesperadamente"
        display2_pid=$(start_display_instance "$DISPLAY2_NAME" "$DISPLAY2_IP" "$DISPLAY2_DHCP_START" "$DISPLAY2_DHCP_END" "$DISPLAY2_SOUND_OUTPUT" "$DISPLAY2_PLAYER_SELECT" "display2")
    fi
done