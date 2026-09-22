#!/bin/bash
#################################################################################
# Teste de integração do LazyCast sem hardware.
#
# Sobe um simulador de fonte Miracast (tests/mock_source.py), que faz o papel
# do Windows/Android, e roda o receiver (d2.py) contra ele em 127.0.0.1.
# Verifica a negociação RTSP M1..M7, o lançamento do player, o keep-alive e o
# encerramento por TEARDOWN. Também roda all.sh e all-dual.sh com wpa_cli,
# ifconfig, busybox e sudo simulados para validar os scripts de orquestração.
#
# Uso: ./test-integration.sh [receiver|all|dual|everything]
#################################################################################
set -u

cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
WORK="$(mktemp -d /tmp/lazycast-test.XXXXXX)"
STUBS="$WORK/bin"
PASSED=0
FAILED=0

cleanup() {
    pkill -f "$WORK" 2>/dev/null
    pkill -f "tests/mock_source.py" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "✗ $1"; FAILED=$((FAILED + 1)); }
check() { # check "descrição" comando...
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

wait_for() { # wait_for segundos arquivo padrão
    local i
    for ((i = 0; i < $1 * 10; i++)); do
        grep -q -- "$3" "$2" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

make_stubs() {
    mkdir -p "$STUBS"
    # sudo: executa o comando sem privilégio (os stubs abaixo não precisam)
    printf '#!/bin/bash\nexec "$@"\n' > "$STUBS/sudo"
    # wpa_cli: simula wpa_supplicant com uma interface p2p já criada
    cat > "$STUBS/wpa_cli" <<'EOF'
#!/bin/bash
echo "wpa_cli $*" >> "$STUB_LOG"
args=("$@")
case "${args[*]}" in
    *interface*) printf 'Available interfaces:\np2p-dev-wlan0\np2p-wlan0-0\nwlan0\n' ;;
    *status*) echo "freq=2437" ;;
    *list_networks*) echo "network id / ssid / bssid / flags" ;;
    *p2p_group_add*) echo "OK" ;;
    *) echo "OK" ;;
esac
EOF
    printf '#!/bin/bash\necho "ifconfig $*" >> "$STUB_LOG"\n' > "$STUBS/ifconfig"
    printf '#!/bin/bash\necho "busybox $*" >> "$STUB_LOG"\n' > "$STUBS/busybox"
    # players: registram a chamada e ficam vivos como um player real
    for p in vlc cvlc; do
        printf '#!/bin/bash\necho "%s $*" >> "$STUB_LOG"\ntrap "kill \\$!; exit 0" TERM INT\nsleep 300 & wait\n' "$p" > "$STUBS/$p"
    done
    chmod +x "$STUBS"/*
    export STUB_LOG="$WORK/stub-calls.log"
    : > "$STUB_LOG"
}

# Cópia isolada do projeto para não sujar o checkout (all.sh faz sed em d2.py)
make_sandbox() {
    local dir="$WORK/$1"
    mkdir -p "$dir/control"
    cp "$ROOT"/*.py "$ROOT"/*.sh "$dir/"
    mkdir -p "$dir/tests" && cp "$ROOT"/tests/*.py "$dir/tests/"
    echo "$dir"
}

start_source() { # start_source dir [args...]
    local dir="$1"; shift
    python3 "$ROOT/tests/mock_source.py" "$@" > "$dir/source.log" 2>&1 &
    echo $! > "$dir/source.pid"
    wait_for 5 "$dir/source.log" "aguardando receiver" || { fail "mock source não subiu"; cat "$dir/source.log"; return 1; }
}

source_result() { # source_result dir -> aguarda o simulador terminar e devolve o exit code
    local pid; pid=$(cat "$1/source.pid")
    local i
    for ((i = 0; i < 600; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    wait "$pid" 2>/dev/null
}

test_receiver() { # test_receiver [args extras do mock_source]
    echo ""
    echo "== d2.py contra fonte Miracast simulada ${*:+($*)} =="
    local dir; dir=$(make_sandbox "receiver$#")
    : > "$STUB_LOG"
    start_source "$dir" "$@" || return
    (cd "$dir" && PATH="$STUBS:$PATH" timeout 60 python3 d2.py 127.0.0.1 > receiver.log 2>&1; echo $? > receiver.exit)
    source_result "$dir"; local src=$?
    local before=$FAILED

    check "fonte: negociação M1-M7 concluída" grep -q "negociação M1-M7 concluída" "$dir/source.log"
    check "fonte: receiver respondeu keep-alive e TEARDOWN e fechou a sessão" test "$src" -eq 0
    check "receiver: imprimiu 'Negotiation successful'" grep -q "Negotiation successful" "$dir/receiver.log"
    check "receiver: player lançado (vlc em sistema não-Pi)" grep -q "^vlc " "$STUB_LOG"
    check "receiver: player usa rtp://0.0.0.0:1028" grep -q "rtp://0.0.0.0:1028" "$STUB_LOG"
    check "receiver: sem traceback" bash -c "! grep -q Traceback '$dir/receiver.log'"
    check "receiver: saiu com código 0" test "$(cat "$dir/receiver.exit")" = "0"
    check "receiver: encerrou o player no TEARDOWN" bash -c '! pgrep -x vlc >/dev/null'
    if [ "$FAILED" -gt "$before" ]; then
        echo "--- source.log"; tail -30 "$dir/source.log"
        echo "--- receiver.log"; tail -30 "$dir/receiver.log"
        echo "--- stubs"; cat "$STUB_LOG"
    fi
}

test_all_sh() {
    echo ""
    echo "== all.sh com wpa_cli/udhcpd simulados =="
    local dir; dir=$(make_sandbox all)
    cat > "$dir/lazycast-config.conf" <<'EOF'
MANAGE_FREQUENCY=0
DISPLAY1_NAME="TesteSingle"
DISPLAY1_IP="127.0.0.1"
DISPLAY1_DHCP_START="127.0.0.1"
DISPLAY1_DHCP_END="127.0.0.1"
DISPLAY1_SOUND_OUTPUT=1
DISPLAY1_PLAYER_SELECT=0
EOF
    start_source "$dir" || return
    (cd "$dir" && PATH="$STUBS:$PATH" timeout 60 bash all.sh > all.log 2>&1) &
    local all_pid=$!
    source_result "$dir"; local src=$?
    sleep 1
    kill "$all_pid" 2>/dev/null; pkill -P "$all_pid" 2>/dev/null
    local before=$FAILED
    check "all.sh: imprimiu 'The display is ready'" grep -q "The display is ready" "$dir/all.log"
    check "all.sh: nome do display vindo do conf" grep -q "TesteSingle" "$dir/all.log"
    check "all.sh: configurou IP na interface p2p" grep -q "ifconfig p2p-wlan0-0 127.0.0.1" "$STUB_LOG"
    check "all.sh: udhcpd.conf gerado com start/end do conf" grep -q "start.127.0.0.1" "$dir/udhcpd.conf"
    check "all.sh: player_select do conf aplicado em d2.py" grep -q "^player_select = 0" "$dir/d2.py"
    check "all.sh: sound_output do conf aplicado em d2.py" grep -q "^sound_output_select = 1" "$dir/d2.py"
    check "all.sh: d2.py negociou com a fonte" test "$src" -eq 0
    check "all.sh: sem 'command not found'" bash -c "! grep -q 'command not found' '$dir/all.log'"
    if [ "$FAILED" -gt "$before" ]; then
        echo "--- all.log"; tail -40 "$dir/all.log"
        echo "--- source.log"; tail -20 "$dir/source.log"
        echo "--- stubs"; cat "$STUB_LOG"
    fi
}

test_all_dual_sh() {
    echo ""
    echo "== all-dual.sh com wpa_cli/udhcpd simulados =="
    local dir; dir=$(make_sandbox dual)
    echo "bin" > "$dir/h264/h264.bin"
    cat > "$dir/lazycast-config.conf" <<'EOF'
DISPLAY_MODE=2
DISPLAY1_NAME="TelaA"
DISPLAY1_IP="127.0.0.1"
DISPLAY1_DHCP_START="127.0.0.1"
DISPLAY1_DHCP_END="127.0.0.1"
DISPLAY1_SOUND_OUTPUT=0
DISPLAY1_PLAYER_SELECT=0
DISPLAY2_NAME="TelaB"
DISPLAY2_IP="127.0.0.2"
DISPLAY2_DHCP_START="127.0.0.2"
DISPLAY2_DHCP_END="127.0.0.2"
DISPLAY2_SOUND_OUTPUT=1
DISPLAY2_PLAYER_SELECT=0
EOF
    start_source "$dir" || return
    (cd "$dir" && PATH="$STUBS:$PATH" timeout 60 bash all-dual.sh > dual.log 2>&1) &
    local dual_pid=$!
    source_result "$dir"; local src=$?
    sleep 1
    kill -INT "$dual_pid" 2>/dev/null; sleep 1
    pkill -f "$dir" 2>/dev/null
    local before=$FAILED
    check "dual: duas instâncias iniciadas" bash -c "grep -q 'Instância TelaA iniciada' '$dir/dual.log' && grep -q 'Instância TelaB iniciada' '$dir/dual.log'"
    check "dual: PIDs numéricos capturados" grep -Eq "Display 1 PID: [0-9]+$" "$dir/dual.log"
    check "dual: log da instância 1 criado" test -s "$dir/lazycast_instance_display1/lazycast_display1.log"
    check "dual: 'The display is ready' na instância 1" grep -q "The display is ready" "$dir/lazycast_instance_display1/lazycast_display1.log"
    check "dual: instância 1 (127.0.0.1) negociou com a fonte" test "$src" -eq 0
    check "dual: player/sound do conf aplicados na instância 2" bash -c "grep -q '^sound_output_select = 1' '$dir/lazycast_instance_display2/d2.py'"
    check "dual: sem 'command not found'" bash -c "! grep -q 'command not found' '$dir'/dual.log '$dir'/lazycast_instance_display*/*.log"
    if [ "$FAILED" -gt "$before" ]; then
        echo "--- dual.log"; tail -40 "$dir/dual.log"
        for f in "$dir"/lazycast_instance_display*/*.log; do echo "--- $f"; tail -20 "$f"; done
        echo "--- source.log"; tail -20 "$dir/source.log"
    fi
}

make_stubs
case "${1:-everything}" in
    receiver) test_receiver; test_receiver --coalesce ;;
    all) test_all_sh ;;
    dual) test_all_dual_sh ;;
    everything) test_receiver; test_receiver --coalesce; test_all_sh; test_all_dual_sh ;;
    *) echo "uso: $0 [receiver|all|dual|everything]"; exit 2 ;;
esac

echo ""
echo "=========================================="
echo "Testes passados: $PASSED"
echo "Testes falhados: $FAILED"
echo "=========================================="
[ "$FAILED" -eq 0 ]
