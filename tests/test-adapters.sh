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

# --- layout das janelas (labwc): wlr-randr/pgrep/kill simulados e rc.xml em diretório temporário
export XDG_CONFIG_HOME=$(mktemp -d)
command() { [ "$1" = "-v" ] && [ "$2" = "wlr-randr" ] && return 0; builtin command "$@"; }
pgrep() { echo 4242; }
kill() { :; }
sleep() { :; }
# a) só a saída virtual do VNC (767x660), 2 telas -> lado a lado, 16:9
wlr-randr() { printf 'NOOP-1 "Headless output 2"\n  Make: (null)\n  Modes:\n    767x660 px (current)\n  Position: 0,0\n'; }
write_vlc_layout 2 && ok "layout aplicado (saída virtual)" || bad "layout virtual" falhou
R="$XDG_CONFIG_HOME/labwc/rc.xml"
grep -q 'name="MoveTo" x="0" y="40"' "$R" && grep -q 'name="MoveTo" x="383" y="40"' "$R" && ok "janelas lado a lado (x=0 e x=383)" || bad "lado a lado" "$(cat $R)"
grep -q 'width="383" height="215"' "$R" && ok "tamanho proporcional 16:9 (383x215)" || bad "16:9" "$(cat $R)"
grep -q 'lazycast-layout' "$R" && ok "arquivo marcado como do LazyCast" || bad "marca" ""
# b) dois HDMI reais -> cada tela em tela cheia no seu monitor (esq -> dir)
wlr-randr() { printf 'HDMI-A-2 "B"\n  Modes:\n    1920x1080 px, 60.0 Hz (preferred, current)\n  Position: 1920,0\nHDMI-A-1 "A"\n  Modes:\n    1920x1080 px, 60.0 Hz (preferred, current)\n  Position: 0,0\nNOOP-1 "x"\n  Modes:\n    767x660 px (current)\n  Position: 0,0\n'; }
write_vlc_layout 2 && ok "layout aplicado (2 HDMI)" || bad "layout hdmi" falhou
grep -A1 'title="LazyCast-1"' "$R" | grep -q 'output="HDMI-A-1"' && ok "tela 1 no monitor da esquerda (HDMI-A-1)" || bad "tela1" "$(cat $R)"
grep -A1 'title="LazyCast-2"' "$R" | grep -q 'output="HDMI-A-2"' && ok "tela 2 no monitor da direita (HDMI-A-2)" || bad "tela2" "$(cat $R)"
grep -q 'ToggleFullscreen' "$R" && ok "tela cheia nos monitores reais" || bad "fullscreen" ""
# c) rc.xml do usuário (sem a marca) não é sobrescrito
echo '<labwc_config/>' > "$R"
if write_vlc_layout 2 >/dev/null; then bad "não deveria sobrescrever" ok; else ok "rc.xml do usuário preservado"; fi
unset -f command pgrep kill sleep wlr-randr

# --- nome aleatório do display
n1=$(random_animal_name)
[[ "$n1" =~ ^LazyCast-[A-Z][a-z]+$ ]] && ok "nome aleatório no formato LazyCast-Animal ($n1)" || bad "formato do nome" "$n1"
seen=""; for _i in $(seq 1 40); do seen="$seen $(random_animal_name)"; done
distinct=$(echo $seen | tr ' ' '\n' | sort -u | wc -l)
[ "$distinct" -gt 5 ] && ok "o sorteio varia ($distinct nomes distintos em 40)" || bad "variedade do sorteio" "$distinct"

echo ""
echo "Resultado: $PASSED passou, $FAILED falhou"
[ "$FAILED" -eq 0 ]
