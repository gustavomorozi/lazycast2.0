#!/bin/bash
#################################################################################
# Testa a detecção de adaptadores Wi-Fi (lib-p2p.sh) com iw/wpa_cli simulados:
# por capacidade P2P, ordem estável independente de nome/porta e fixação por MAC.
# Não exige hardware. Uso: ./tests/test-adapters.sh
#################################################################################
cd "$(dirname "$0")/.." || exit 1
source ./lib-p2p.sh

PASSED=0; FAILED=0
ok()   { echo "✓ $1"; PASSED=$((PASSED + 1)); }
bad()  { echo "✗ $1 (obtido: [$2])"; FAILED=$((FAILED + 1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2"; fi; }

# --- simulação: interno brcmfmac (wlan0), USB com P2P (wlan7, MAC menor), USB sem P2P RT5370 (wlan2)
iw() {
    case "$*" in
        "dev") printf 'phy#0\n\tInterface wlan0\nphy#2\n\tInterface wlan2\nphy#3\n\tInterface wlan7\nphy#0\n\tInterface p2p-wlan0-5\n' ;;
        "dev wlan0 info") echo "wiphy 0" ;;
        "dev wlan2 info") echo "wiphy 2" ;;
        "dev wlan7 info") echo "wiphy 3" ;;
        "phy phy0 info"|"phy phy3 info")
            printf 'Wiphy x\n\tSupported interface modes:\n\t\t * managed\n\t\t * AP\n\t\t * P2P-client\n\t\t * P2P-GO\n\t\t * P2P-device\n\tBand 1:\n' ;;
        "phy phy2 info")
            printf 'Wiphy x\n\tSupported interface modes:\n\t\t * IBSS\n\t\t * managed\n\t\t * AP\n\t\t * monitor\n\t\t * mesh point\n\tBand 1:\n' ;;
    esac
}
sudo() { "$@"; }
wpa_cli() { printf 'Available interfaces:\np2p-dev-wlan0\nwlan2\np2p-dev-wlan7\nwlan0\nwlan7\n'; }
iface_mac() { case "$1" in wlan0) echo d8:3a:dd:be:91:ec ;; wlan2) echo 7c:dd:90:af:e4:91 ;; wlan7) echo 00:11:22:33:44:55 ;; esac; }
iface_bus() { case "$1" in wlan0) echo interno ;; *) echo usb ;; esac; }
iface_driver() { case "$1" in wlan0) echo brcmfmac ;; wlan2) echo rt2800usb ;; wlan7) echo mt76x2u ;; esac; }

eq "interfaces físicas excluem p2p-*" "$(wifi_ifaces | tr '\n' ' ')" "wlan0 wlan2 wlan7 "
phy_supports_p2p phy0 && ok "brcmfmac (P2P-GO + P2P-client) é compatível" || bad "brcmfmac compatível" no
phy_supports_p2p phy2 && bad "RT5370 sem P2P não pode ser compatível" sim || ok "RT5370 (sem P2P) é rejeitado"
eq "ordem estável: interno primeiro, depois USB compatível; RT5370 fora" "$(list_p2p_devs | tr '\n' ' ')" "p2p-dev-wlan0 p2p-dev-wlan7 "
eq "fixar por nome da interface" "$(resolve_p2p_dev_pin wlan7)" "p2p-dev-wlan7"
eq "fixar por MAC (maiúsculas também)" "$(resolve_p2p_dev_pin 00:11:22:33:44:55)" "p2p-dev-wlan7"
eq "fixar por MAC em maiúsculas" "$(resolve_p2p_dev_pin D8:3A:DD:BE:91:EC)" "p2p-dev-wlan0"
eq "adaptador inexistente não resolve" "$(resolve_p2p_dev_pin aa:bb:cc:dd:ee:ff)" ""
print_wifi_adapters > /tmp/lc_adapters.txt; n=$?
eq "print_wifi_adapters retorna nº de compatíveis" "$n" "2"
grep -q "rt2800usb.*NÃO" /tmp/lc_adapters.txt && ok "tabela avisa que o RT5370 não serve" || bad "aviso RT5370" "$(cat /tmp/lc_adapters.txt)"

# Mesma lista se o adaptador USB trocar de nome/porta: a ordem depende de bus+MAC, não do nome
iw() { case "$*" in
    "dev") printf 'phy#0\n\tInterface wlan0\nphy#3\n\tInterface wlx001122334455\n' ;;
    "dev wlan0 info") echo "wiphy 0" ;; "dev wlx001122334455 info") echo "wiphy 3" ;;
    "phy phy0 info"|"phy phy3 info") printf 'Wiphy x\n\tSupported interface modes:\n\t\t * P2P-client\n\t\t * P2P-GO\n\tBand 1:\n' ;;
esac; }
wpa_cli() { printf 'Available interfaces:\np2p-dev-wlan0\nwlx001122334455\nwlan0\n'; }
iface_mac() { case "$1" in wlan0) echo d8:3a:dd:be:91:ec ;; *) echo 00:11:22:33:44:55 ;; esac; }
iface_bus() { case "$1" in wlan0) echo interno ;; *) echo usb ;; esac; }
eq "USB com nome wlx… sem p2p-dev usa a própria interface de controle" "$(list_p2p_devs | tr '\n' ' ')" "p2p-dev-wlan0 wlx001122334455 "

# --- posicionamento do VLC por monitor (xrandr simulado; ordem esquerda -> direita)
xrandr() { printf 'Screen 0: minimum 320 x 200
XWAYLAND1 connected 1280x720+1920+0 (normal left inverted) 0mm x 0mm
XWAYLAND0 connected primary 1920x1080+0+0 (normal left inverted) 0mm x 0mm
XWAYLAND2 disconnected (normal left inverted)
'; }
eq "VLC monitor 0 = mais à esquerda" "$(vlc_args_for_screen 0)" "--no-fullscreen --no-video-deco --video-x=0 --video-y=0 --width=1920 --height=1080"
eq "VLC monitor 1 = à direita" "$(vlc_args_for_screen 1)" "--no-fullscreen --no-video-deco --video-x=1920 --video-y=0 --width=1280 --height=720"
eq "VLC monitor inexistente = vazio" "$(vlc_args_for_screen 2)" ""

echo ""
echo "Resultado: $PASSED passou, $FAILED falhou"
[ "$FAILED" -eq 0 ]
