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

#################################################################################
# Layout das janelas do VLC no labwc (Wayland): com 2+ telas (dual), cada janela recebe um título
# (LazyCast-1, LazyCast-2) e uma regra de janela do labwc a posiciona:
#   - monitores HDMI reais >= nº de telas -> cada tela em TELA CHEIA no seu monitor (esq -> dir)
#   - senão (ex.: só a saída virtual do VNC/headless) -> janelas LADO A LADO, proporcionais 16:9,
#     cabendo na saída disponível.
# Motivo: no Wayland o compositor decide a posição; --video-x/--width do VLC são ignorados (testado
# no Pi 5 com labwc 0.20: a janela abre centralizada no tamanho do vídeo). O título é aplicado
# com --video-title e a regra por título foi validada no hardware.
# O arquivo só é criado/alterado se não existir ou tiver a marca lazycast-layout (não sobrescreve
# um rc.xml do usuário). Retorna 0 se aplicou a regra (então o VLC NÃO deve usar --fullscreen).
#################################################################################
labwc_outputs() {
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" wlr-randr 2>/dev/null | awk '
        /^[^ ]/ { name = $1 }
        /px/ && /current/ { split($1, a, "x"); w = a[1]; h = a[2] }
        /Position:/ { split($2, p, ","); print name, w, h, p[1], p[2] }'
}

write_vlc_layout() {
    local slots="$1" cfg rules="" i name w h x y ww hh panel=40
    local -a outs real
    command -v wlr-randr >/dev/null 2>&1 || return 1
    pgrep -x labwc >/dev/null 2>&1 || return 1
    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/labwc/rc.xml"
    if [ -f "$cfg" ] && ! grep -q 'lazycast-layout' "$cfg"; then
        echo "AVISO: $cfg já existe e não é do LazyCast; layout das janelas não alterado."
        return 1
    fi
    mapfile -t outs < <(labwc_outputs)
    [ "${#outs[@]}" -gt 0 ] || return 1
    mapfile -t real < <(printf '%s\n' "${outs[@]}" | grep -v '^NOOP' | sort -k4,4n)

    if [ "${#real[@]}" -ge 1 ]; then
        # Há pelo menos um monitor HDMI real: cada tela vai em tela cheia (nunca dividida). Com menos monitores
        # que telas, mais de uma tela mira no mesmo monitor (ex.: 1 monitor + 2 telas): a que estiver por cima
        # ocupa a tela toda; não reduzimos a janela para caber as duas lado a lado.
        for ((i = 0; i < slots; i++)); do
            read -r name w h x y <<< "${real[$((i % ${#real[@]}))]}"
            rules+="    <windowRule title=\"LazyCast-$((i + 1))\">
      <action name=\"MoveToOutput\" output=\"$name\"/>
      <action name=\"ToggleFullscreen\"/>
    </windowRule>
"
        done
    else
        # Nenhum monitor real (só a saída virtual do VNC): tela cheia não faz sentido para administração remota,
        # então divide em blocos pequenos lado a lado para dar para ver as duas ao mesmo tempo.
        read -r name w h x y <<< "${outs[0]}"
        ww=$((w / slots)); hh=$((ww * 9 / 16))
        [ "$hh" -gt $((h - panel)) ] && { hh=$((h - panel)); ww=$((hh * 16 / 9)); }
        for ((i = 0; i < slots; i++)); do
            rules+="    <windowRule title=\"LazyCast-$((i + 1))\">
      <action name=\"MoveTo\" x=\"$((x + i * ww))\" y=\"$((y + panel))\"/>
      <action name=\"ResizeTo\" width=\"$ww\" height=\"$hh\"/>
    </windowRule>
"
        done
    fi
    mkdir -p "$(dirname "$cfg")"
    printf '<?xml version="1.0"?>\n<!-- lazycast-layout (gerado pelo LazyCast; apague para desfazer) -->\n<labwc_config>\n  <windowRules>\n%s  </windowRules>\n</labwc_config>\n' "$rules" > "$cfg"
    # labwc --reconfigure exige LABWC_PID (só existe dentro da sessão); SIGHUP recarrega a configuração
    kill -HUP "$(pgrep -x labwc | head -1)" 2>/dev/null
    sleep 1
    return 0
}

# Nome padrão do display: LazyCast-<animal em inglês> aleatório (ex.: LazyCast-Fox), sorteado a cada
# instalação nova; a reinstalação mantém o nome existente. Pode ser trocado depois no painel gráfico
# (aba Configurações) ou em DISPLAY1_NAME no lazycast-config.conf.
LAZYCAST_ANIMALS=(Fox Wolf Bear Eagle Tiger Lion Panda Koala Otter Falcon Dolphin Whale Shark Turtle
    Rabbit Deer Moose Bison Lynx Puma Jaguar Leopard Cheetah Hawk Owl Raven Swan Heron Crane Penguin
    Seal Walrus Badger Beaver Hedgehog Squirrel Gecko Iguana Cobra Camel Llama Alpaca Zebra Giraffe
    Rhino Hippo Gorilla Monkey Lemur Sloth Ferret Marten Panther Bobcat Coyote Gazelle Antelope Pelican)
random_animal_name() {
    echo "LazyCast-${LAZYCAST_ANIMALS[RANDOM % ${#LAZYCAST_ANIMALS[@]}]}"
}

# Nome da REDE: o SSID do grupo Wi-Fi Direct é "DIRECT-xy" + p2p_ssid_postfix. Com o postfix, a rede
# aparece como DIRECT-D9-LazyCast-Gecko em qualquer lista de Wi-Fi (testado no Pi 5; o Windows/Android
# listam o receptor pelo device_name, que recebe o mesmo nome). O SSID tem no máx. 32 bytes, e
# "DIRECT-xy" ocupa 9: o postfix ("-" + nome) fica limitado a 23 caracteres.
network_postfix() {
    local n
    n=$(printf '%s' "$1" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')
    printf -- '-%s' "${n:0:22}"
}

# uso: set_p2p_network_name <p2p-dev> <nome>   (o "--" evita que o wpa_cli leia o "-" como opção)
set_p2p_network_name() {
    sudo wpa_cli -i "$1" -- set p2p_ssid_postfix "$(network_postfix "$2")" >/dev/null
}

#################################################################################
# Como o vídeo recebido é mostrado (LAZYCAST_VLC_MODE):
#   window - VLC em janela/tela cheia (há monitor HDMI ligado): 1 tela = tela cheia; 2 telas = layout
#            do labwc (um por monitor ou lado a lado)
#   hidden - NENHUM monitor ligado (ex.: só a saída virtual do VNC): o VLC decodifica sem abrir janela
#            (--vout=dummy) para não cobrir a área de trabalho; o vídeo só aparece na prévia do painel
#            ("Ver telas", por snapshot). Testado no Pi 5: o snapshot funciona sem janela.
# A decisão é tomada ao iniciar o serviço; ligou/desligou um monitor -> reinicie o LazyCast.
#################################################################################
setup_vlc_output() {
    local slots="$1" nreal
    export LAZYCAST_VLC_MODE=window
    if command -v wlr-randr >/dev/null 2>&1 && pgrep -x labwc >/dev/null 2>&1; then
        nreal=$(labwc_outputs | grep -vc '^NOOP')
        if [ "$nreal" -lt 1 ]; then
            export LAZYCAST_VLC_MODE=hidden
            echo "Nenhum monitor HDMI ligado: vídeo sem janela (veja em 'Ver telas' no painel)."
            return 0
        fi
    fi
    if [ "$slots" -ge 2 ] && write_vlc_layout "$slots"; then export LAZYCAST_FULLSCREEN=0; fi
    return 0
}

#################################################################################
# Fonte de cada tela (SCREEN1_SOURCE / SCREEN2_SOURCE no lazycast-config.conf):
#   auto | wireless        recebe por Wi-Fi Direct (Miracast)
#   usb:<nome em /dev/v4l/by-id>   capturadora HDMI->USB (UVC), em qualquer porta USB (wired-input.sh)
#   stream:<porta UDP>     tela estendida enviada pela rede, ex.: ffmpeg no Windows (wired-input.sh)
# As telas COM FIO não usam o Wi-Fi: as sem fio ficam com os IPs do DHCP em ordem (.80, .81).
#################################################################################
screen_source() { local v="SCREEN$(( $1 + 1 ))_SOURCE"; echo "${!v:-auto}"; }
is_wired_source() { case "$1" in usb:?* | stream:[0-9]*) return 0 ;; *) return 1 ;; esac; }
# índices (0-based) das telas sem fio entre as $1 telas
wireless_screens() { local n="$1" k; for ((k = 0; k < n; k++)); do is_wired_source "$(screen_source "$k")" || echo "$k"; done; }
# porta RTP (também identifica o canal de snapshot lc<porta>-) e argumentos extras do VLC da tela k
screen_rtp() { local v="DISPLAY$(( $1 + 1 ))_RTP_PORT"; echo "${!v:-$(( 1028 + 2 * $1 ))}"; }
screen_vlc_args() { local v="DISPLAY$(( $1 + 1 ))_VLC_ARGS"; echo "${!v}"; }
