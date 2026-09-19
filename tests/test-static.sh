#!/bin/bash
#################################################################################
# Testes estáticos de regressão (Pi 5 / dual display). Não exigem hardware nem Linux
# completo: validam sintaxe, ausência de padrões que já causaram bugs e consistência
# de configuração. Uso: ./tests/test-static.sh
#################################################################################
cd "$(dirname "$0")/.." || exit 1

PASSED=0
FAILED=0
pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "✗ $1"; FAILED=$((FAILED + 1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }

# Sintaxe
for f in lib-p2p.sh all.sh all-dual.sh install.sh install-service.sh setup-hdmi.sh lazycast-background.sh; do
    check "bash -n $f" bash -n "$f"
done
PY=$(command -v python3 || command -v python)
for f in d2.py d2-multi.py; do
    check "py_compile $f" "$PY" -c "import ast,sys; ast.parse(open('$f',encoding='utf-8').read())"
done

# Fim de linha LF (CRLF quebra o shebang no Pi)
for f in *.sh *.py lazycast.service; do
    check "sem CRLF: $f" bash -c "! grep -q \$'\r' '$f'"
done

# Pi 5: setup-hdmi.sh nunca pode gravar fkms nem hdmi_mode legado
check "setup-hdmi.sh não adiciona vc4-fkms-v3d" bash -c "! grep -q 'add_config_line.*fkms' setup-hdmi.sh && ! grep -q 'echo \"dtoverlay=vc4-fkms' setup-hdmi.sh"
check "setup-hdmi.sh não adiciona hdmi_mode" bash -c "! grep -q 'add_config_line' setup-hdmi.sh"

# Dual display: sem pkill global de vlc e sem porta RTP fixa duplicada
check "d2.py sem 'pkill vlc' global" bash -c "! grep -q \"system('pkill vlc')\" d2.py d2-multi.py && ! grep -q '^[[:space:]]*pkill vlc' all-dual.sh"
check "d2.py sem 'ps au' em laço" bash -c "! grep -q \"popen('ps au')\" d2.py d2-multi.py"
check "d2.py usa rtp_port (sem 1028 fixo no código ativo)" bash -c "! grep -v '^[[:space:]]*#' d2.py | grep -v omxplayer | grep -q 'unicast 1028\|client_port=1028\|rtp://0.0.0.0:1028'"
check "d2-multi.py usa rtp_port" bash -c "! grep -v '^[[:space:]]*#' d2-multi.py | grep -v omxplayer | grep -q 'unicast 1028\|client_port=1028\|rtp://0.0.0.0:1028'"

# Configuração gerada: portas e telas distintas por display
port1=$(grep -o 'DISPLAY1_RTP_PORT=[0-9]*' install.sh | head -1 | cut -d= -f2)
port2=$(grep -o 'DISPLAY2_RTP_PORT=[0-9]*' install.sh | head -1 | cut -d= -f2)
check "install.sh define portas RTP distintas ($port1/$port2)" bash -c "[ -n '$port1' ] && [ -n '$port2' ] && [ '$port1' != '$port2' ]"
check "all-dual.sh possui defaults de porta distintos" bash -c "grep -q 'DISPLAY1_RTP_PORT:-1028' all-dual.sh && grep -q 'DISPLAY2_RTP_PORT:-1030' all-dual.sh"

# Instalador no Pi 5 não compila OpenMAX
check "install.sh força player 0 no Pi 5" grep -q 'PLAYER_SELECT=0' install.sh
check "Makefile padrão só compila control" bash -c "grep -q '^all: control$' Makefile"

# Somente Pi 5: sem OpenMAX/legado no repositório
check "sem diretórios h264/ e player/" bash -c "[ ! -d h264 ] && [ ! -d player ]"
check "d2.py sem referências a h264.bin/player.bin/omxplayer ativos" bash -c "! grep -v '^[[:space:]]*#' d2.py d2-multi.py | grep -q 'h264.bin\|player.bin\|omxplayer '"
check "d2.py força player_select = 0" bash -c "grep -q '^player_select = 0' d2.py && grep -q '^player_select = 0' d2-multi.py"
check "install.sh recusa hardware não-Pi5 sem --force" bash -c "grep -q 'somente o Raspberry Pi 5' install.sh"
check "install.sh aceita --yes" bash -c "grep -q -- '--yes' install.sh"

check "all.sh/all-dual.sh limpam interfaces P2P órfãs" bash -c "grep -q cleanup_orphan_p2p_ifaces all.sh && grep -q cleanup_orphan_p2p_ifaces all-dual.sh"
check "install.sh não referencia player_health_check.sh" bash -c "! grep -q player_health_check install.sh"

check "lib-p2p.sh pausa e retoma o NetworkManager" bash -c "grep -q 'killall -STOP NetworkManager' lib-p2p.sh && grep -q 'killall -CONT NetworkManager' lib-p2p.sh"
check "scripts chamam pause_networkmanager" bash -c "grep -q pause_networkmanager all.sh && grep -q pause_networkmanager all-dual.sh"
check "serviço retoma o NetworkManager ao parar" grep -q "ExecStopPost=.*CONT NetworkManager" lazycast.service

check "all.sh/all-dual.sh ligam wifi_display antes do wfd_subelem_set" bash -c "grep -q 'set wifi_display 1' all.sh && grep -q 'set wifi_display 1' all-dual.sh"

check "scripts registram a autenticação WPS (pbc/pin)" bash -c "grep -q register_wps_auth all.sh && grep -q register_wps_auth all-dual.sh && grep -q set_wps_config_methods all.sh && grep -q 'wps_pbc' lib-p2p.sh && grep -q 'wps_pin any' lib-p2p.sh"
check "DHCP libera o IP ao desconectar (watch_dhcp_release)" bash -c "grep -q watch_dhcp_release lib-p2p.sh && grep -q watch_dhcp_release all.sh && grep -q watch_dhcp_release all-dual.sh"
check "install.sh grava LAZYCAST_AUTH (padrão pbc)" bash -c "grep -q 'LAZYCAST_AUTH=\${LAZYCAST_AUTH:-pbc}' install.sh"
check "install.sh gera LAZYCAST_PIN" grep -q "gen_wps_pin" install.sh
check "PIN gerado tem 8 dígitos e checksum WPS válido" bash -c "source ./lib-p2p.sh; for i in 1 2 3 4 5; do p=\$(gen_wps_pin); [ \${#p} -eq 8 ] || exit 1; a=0; for k in 0 1 2 3 4 5 6 7; do d=\${p:\$k:1}; if [ \$((k%2)) -eq 0 ]; then a=\$((a+3*d)); else a=\$((a+d)); fi; done; [ \$((a%10)) -eq 0 ] || exit 1; done"

check "detecção de adaptadores (tests/test-adapters.sh)" bash tests/test-adapters.sh

# Serviço: ambiente de sessão presente (evita dbus-launch órfão)
check "lazycast.service define XDG_RUNTIME_DIR e D-Bus" bash -c "grep -q XDG_RUNTIME_DIR lazycast.service && grep -q DBUS_SESSION_BUS_ADDRESS lazycast.service"
check "background usa timeout no notify-send" grep -q 'timeout 5 notify-send' lazycast-background.sh

# Regex de pgrep não pode casar install.sh
if command -v pgrep >/dev/null 2>&1; then
    re='(^|[ /])all(-dual)?[.]sh( |$)'
    check "regex do monitor casa './all.sh'" bash -c "echo '/bin/bash ./all.sh' | grep -Eq '$re'"
    check "regex do monitor casa './all-dual.sh'" bash -c "echo '/bin/bash ./all-dual.sh' | grep -Eq '$re'"
    check "regex do monitor NÃO casa 'install.sh'" bash -c "! echo '/bin/bash ./install.sh' | grep -Eq '$re'"
fi

echo ""
echo "Resultado: $PASSED passou, $FAILED falhou"
[ "$FAILED" -eq 0 ]
