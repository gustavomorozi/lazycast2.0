#!/bin/bash
#################################################################################
# Funções compartilhadas de Wi-Fi P2P (usadas por all.sh e all-dual.sh).
#
# O chip Wi-Fi do Raspberry Pi 5 (brcmfmac) aceita UM grupo P2P-GO por vez
# (#{ P2P-client, P2P-GO } <= 1). Se uma interface p2p-wl* sobra no kernel sem
# que o wpa_supplicant a conheça (órfã), ela ocupa essa vaga e todo p2p_group_add
# seguinte falha com "iface validation failed: err=-16" (Device or resource busy).
# O all.sh só procurava grupos listados pelo wpa_cli e repetia a tentativa para sempre.
#################################################################################

# Remove interfaces p2p-wl* presentes no kernel e ausentes do wpa_supplicant.
cleanup_orphan_p2p_ifaces() {
    command -v iw >/dev/null 2>&1 || return 0
    local known kif
    known="$(sudo wpa_cli interface 2>/dev/null)"
    for kif in $(iw dev 2>/dev/null | awk '/Interface p2p-wl/ {print $2}'); do
        if ! echo "$known" | grep -qx "$kif"; then
            echo "Removendo interface P2P órfã do kernel: $kif"
            sudo iw dev "$kif" del 2>/dev/null
        fi
    done
}

# O NetworkManager (Pi 5 / Bookworm-Trixie) desliga o grupo P2P menos de 1 s após o
# wpa_supplicant criá-lo (P2P-GROUP-STARTED seguido de AP-DISABLED). Testado no Pi 5:
# com o NetworkManager pausado (SIGSTOP) o grupo permanece; ativo, é removido, mesmo com
# unmanaged-devices. Por isso ele é pausado enquanto o LazyCast roda e retomado ao sair.
# Efeito: o Wi-Fi já conectado continua, mas não reconecta sozinho durante o uso.
NM_PAUSED=0

# Espera (até ~60 s) a rede subir no boot para não pausar o NetworkManager antes de conectar.
wait_for_network() {
    command -v nmcli >/dev/null 2>&1 || return 0
    # já pausado (ex.: all-dual.sh chamou all.sh): nmcli não responde, então não há o que esperar
    ps -o stat= -C NetworkManager 2>/dev/null | grep -q '^T' && return 0
    local i
    for i in $(seq 1 30); do
        nmcli -t -f STATE general 2>/dev/null | grep -q '^connected' && return 0
        sleep 2
    done
}

resume_networkmanager() {
    if [ "$NM_PAUSED" = "1" ]; then
        sudo killall -CONT NetworkManager 2>/dev/null
        NM_PAUSED=0
    fi
}

pause_networkmanager() {
    pgrep -x NetworkManager >/dev/null 2>&1 || return 0
    wait_for_network
    sudo killall -STOP NetworkManager 2>/dev/null && NM_PAUSED=1
    trap 'resume_networkmanager; exit 0' INT TERM HUP
    trap 'resume_networkmanager' EXIT
}

# Autenticação de quem conecta (LAZYCAST_AUTH no lazycast-config.conf):
#   pbc (padrão) - SEM PIN: o P2P device anuncia só "botão" e o botão WPS do grupo é mantido
#                  ativo (renovado a cada 90 s). Testado no Pi 5 com Android e Windows.
#                  Atenção: qualquer aparelho ao alcance do Wi-Fi pode espelhar na tela.
#   pin          - a fonte pede o PIN de LAZYCAST_PIN (wps_pin any).
# (O commit que "removeu o PIN" deixou o Windows/Android pedindo PIN sem nenhum registrado.)

# Método anunciado nas respostas de descoberta; chamar ANTES do p2p_group_add.
set_wps_config_methods() {
    local dev="$1"
    if [ "${LAZYCAST_AUTH:-pbc}" = "pin" ]; then
        sudo wpa_cli -i "$dev" set config_methods "keypad" >/dev/null
    else
        sudo wpa_cli -i "$dev" set config_methods "virtual_push_button physical_push_button" >/dev/null
    fi
}

# Enquanto a interface do grupo existir, renova o botão WPS (a janela dura ~120 s).
keep_pbc_active() {
    local g="$1"
    while [ -d "/sys/class/net/$g" ]; do
        sudo wpa_cli -i "$g" wps_pbc >/dev/null 2>&1
        sleep 90
    done
}

# Chamar depois que o grupo existe.
register_wps_auth() {
    local group_if="$1"
    if [ "${LAZYCAST_AUTH:-pbc}" = "pin" ]; then
        if [ -z "$LAZYCAST_PIN" ]; then
            echo "AVISO: LAZYCAST_AUTH=pin mas LAZYCAST_PIN vazio; execute ./install.sh para gerar um PIN."
            return 1
        fi
        sudo wpa_cli -i "$group_if" wps_pin any "$LAZYCAST_PIN" >/dev/null
    else
        keep_pbc_active "$group_if" >/dev/null 2>&1 &
    fi
}

# O pool DHCP tem UM endereço (start=end). Sem isto, o 1º aparelho (ex.: celular) prende o IP pelo
# tempo do aluguel e o 2º (ex.: Windows) não recebe DHCP e falha ao conectar. Observa as estações
# Wi-Fi do grupo (a cada 1 s) e, quando a última desconecta, zera os leases e reinicia o udhcpd (libera na hora).
# uso: watch_dhcp_release <interface do grupo> <conf do udhcpd> <arquivo de leases>
watch_dhcp_release() {
    local g="$1" conf="$2" lease="$3" prev=0 n
    while [ -d "/sys/class/net/$g" ]; do
        n=$(iw dev "$g" station dump 2>/dev/null | grep -c '^Station')
        if [ "$n" -lt "$prev" ]; then
            # Alguém saiu: zera os leases e reinicia o udhcpd. Quem continua conectado mantém o IP (o
            # udhcpd confirma no renovar) e o busybox não oferece IP que responde ARP; o IP livre
            # volta ao pool na hora (pool de 1 IP no modo single, 2 no modo de grupo compartilhado).
            echo "Aparelho desconectou: liberando o IP (DHCP)"
            sudo pkill -f "[u]dhcpd $conf" 2>/dev/null
            rm -f "$lease"
            sudo busybox udhcpd "$conf"
        fi
        prev=$n
        sleep 1
    done
}

# Gera um PIN WPS de 8 dígitos com dígito verificador válido (7 aleatórios + checksum)
gen_wps_pin() {
    local n acc d
    n=$(shuf -i 1000000-9999999 -n 1)
    acc=$(( 3*(n/1000000%10) + (n/100000%10) + 3*(n/10000%10) + (n/1000%10) + 3*(n/100%10) + (n/10%10) + 3*(n%10) ))
    d=$(( (10 - acc % 10) % 10 ))
    echo "${n}${d}"
}

#################################################################################
# Descoberta de adaptadores Wi-Fi: por CAPACIDADE, não por nome (wlan1, wlx...) nem por porta USB.
# Um adaptador serve ao LazyCast se o driver lista P2P-client e P2P-GO nos modos suportados
# (iw phy <phy> info). Chips sem isso (ex.: Ralink RT5370 / rt2800usb) não fazem Wi-Fi Direct.
#################################################################################

# Interfaces Wi-Fi "físicas" (exclui as p2p-* de grupo)
wifi_ifaces() { iw dev 2>/dev/null | awk '/Interface/ {print $2}' | grep -v '^p2p-'; }
iface_phy()    { iw dev "$1" info 2>/dev/null | awk '/wiphy/ {print "phy" $2}'; }
iface_mac()    { cat "/sys/class/net/$1/address" 2>/dev/null; }
iface_driver() { basename "$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)" 2>/dev/null; }
iface_bus() {
    if readlink -f "/sys/class/net/$1/device" 2>/dev/null | grep -q '/usb'; then echo usb; else echo interno; fi
}

# 0 (verdadeiro) se o phy suporta P2P-client e P2P-GO
phy_supports_p2p() {
    local modes
    modes=$(iw phy "$1" info 2>/dev/null | sed -n '/Supported interface modes:/,/Band [0-9]/p')
    echo "$modes" | grep -q 'P2P-GO' && echo "$modes" | grep -q 'P2P-client'
}

# Interface de controle P2P no wpa_supplicant: p2p-dev-<if> se existir; senão a própria <if>
p2p_control_iface() {
    local wl="$1" known
    known=$(sudo wpa_cli interface 2>/dev/null)
    if echo "$known" | grep -qx "p2p-dev-$wl"; then echo "p2p-dev-$wl"
    elif echo "$known" | grep -qx "$wl"; then echo "$wl"
    fi
}

# Interfaces de controle P2P de adaptadores compatíveis, em ordem ESTÁVEL (interno primeiro,
# depois por MAC), para o mesmo display cair sempre no mesmo adaptador, em qualquer porta USB.
list_p2p_devs() {
    local wl phy ctrl bus
    for wl in $(wifi_ifaces); do
        phy=$(iface_phy "$wl")
        phy_supports_p2p "$phy" || continue
        ctrl=$(p2p_control_iface "$wl")
        [ -n "$ctrl" ] || continue
        bus=1; [ "$(iface_bus "$wl")" = "interno" ] && bus=0
        echo "$bus $(iface_mac "$wl") $ctrl"
    done | sort | awk '{print $3}'
}

# Resolve DISPLAYn_P2P_DEV: aceita nome da interface (wlan1), p2p-dev-wlan1 ou o MAC do adaptador
resolve_p2p_dev_pin() {
    local pin="${1,,}" wl
    for wl in $(wifi_ifaces); do
        if [ "$pin" = "$wl" ] || [ "$pin" = "p2p-dev-$wl" ] || [ "$pin" = "$(iface_mac "$wl")" ]; then
            p2p_control_iface "$wl"
            return
        fi
    done
}

# Tabela de adaptadores (usada pelo instalador e pelo all-dual.sh); retorna o nº de compatíveis
print_wifi_adapters() {
    local wl phy ok=0 total=0 status
    echo "Adaptadores Wi-Fi encontrados:"
    for wl in $(wifi_ifaces); do
        total=$((total + 1))
        phy=$(iface_phy "$wl")
        if phy_supports_p2p "$phy"; then status="Wi-Fi Direct: SIM"; ok=$((ok + 1)); else status="Wi-Fi Direct: NÃO (sem P2P-client/P2P-GO; não serve para o LazyCast)"; fi
        printf '  %-10s driver=%-12s %-8s MAC=%s  %s\n' "$wl" "$(iface_driver "$wl")" "$(iface_bus "$wl")" "$(iface_mac "$wl")" "$status"
    done
    [ "$total" -eq 0 ] && echo "  (nenhum)"
    return "$ok"
}

# Argumentos do VLC para posicionar a janela no monitor N (0 = mais à esquerda), via xrandr
# (Xwayland). O VLC roda com --intf dummy e ignora a escolha de tela do Qt, então a posição
# é dada por --video-x/--video-y/--width/--height. Vazio se xrandr não estiver disponível.
vlc_args_for_screen() {
    local n="$1" line w h x y
    command -v xrandr >/dev/null 2>&1 || return 0
    line=$(DISPLAY="${DISPLAY:-:0}" xrandr --query 2>/dev/null | awk '/ connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+[+][0-9]+[+][0-9]+$/) { split($i, a, /[x+]/); print a[1], a[2], a[3], a[4] } }' | sort -k3,3n | sed -n "$((n + 1))p")
    [ -n "$line" ] || return 0
    read -r w h x y <<< "$line"
    echo "--no-fullscreen --no-video-deco --video-x=$x --video-y=$y --width=$w --height=$h"
}
