#!/bin/bash
#################################################################################
# Entrada COM FIO de uma tela do LazyCast (ao lado do Miracast sem fio).
#
#   usb:<nome em /dev/v4l/by-id>  capturadora HDMI->USB (UVC) ligada a QUALQUER porta USB
#   stream:<porta UDP>            tela estendida enviada pela rede (ex.: ffmpeg no Windows)
#
# uso: wired-input.sh <tela 0-based> <fonte>
#
# Mostra o vídeo com o VLC (mesma janela, título LazyCast-N, layout e snapshot da prévia do painel) e
# avisa "Tela N conectada/desconectada". Reinicia sozinho se o VLC cair.
#################################################################################
cd "$(dirname "$0")" || exit 1
source ./lib-p2p.sh
[ -f lazycast-config.conf ] && source lazycast-config.conf

screen="$1"
src="$2"
if [ -z "$screen" ] || [ -z "$src" ]; then
    echo "uso: $0 <tela 0-based> <usb:<by-id>|stream:<porta>>"
    exit 1
fi

n=$((screen + 1))
port=$(screen_rtp "$screen")            # identifica o canal de snapshot (lc<porta>-)
title="LazyCast-$n"
snap_dir="${XDG_RUNTIME_DIR:-/tmp}/lazycast"
mkdir -p "$snap_dir"; chmod 700 "$snap_dir"

case "$src" in
    usb:?*)
        kind=usb
        id="${src#usb:}"
        dev="/dev/v4l/by-id/$id"
        label="USB"
        mrl="v4l2://$dev"
        # 1080p30 em MJPEG é o que a maioria das capturadoras UVC oferece (YUYV em USB 2.0 limita a 720p)
        extra=(${LAZYCAST_USB_VLC_ARGS:---v4l2-width=1920 --v4l2-height=1080 --v4l2-fps=30 --v4l2-chroma=MJPG} --live-caching=50)
        ;;
    stream:[0-9]*)
        kind=stream
        udp_port="${src#stream:}"
        label="rede"
        mrl="udp://@:$udp_port"
        extra=(--network-caching=60 --live-caching=60)
        ;;
    *)
        echo "fonte inválida: $src"
        exit 1
        ;;
esac

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    timeout 5 notify-send --icon=video-display LazyCast "$1" >/dev/null 2>&1
}

# 1 se o VLC desta tela está reproduzindo (RC oldrc por socket unix); usado no modo stream
rc_playing() {
    python3 - "$snap_dir/vlc-$port.sock" <<'PY' 2>/dev/null
import socket, sys, re
try:
    s = socket.socket(socket.AF_UNIX); s.settimeout(1.0)
    s.connect(sys.argv[1]); s.sendall(b'is_playing\n')
    data = s.recv(200).decode(errors='replace'); s.close()
    m = re.search(r'\b([01])\b', data)
    print(m.group(1) if m else 0)
except OSError:
    print(0)
PY
}

vlc_mode_args=()
if [ "$LAZYCAST_VLC_MODE" = "hidden" ]; then
    vlc_mode_args=(--vout=dummy)                 # sem monitor: sem janela (vídeo só na prévia do painel)
elif [ "${LAZYCAST_FULLSCREEN:-1}" = "1" ]; then
    vlc_mode_args=(--fullscreen)
fi

start_vlc() {
    vlc "${vlc_mode_args[@]}" --video-title="$title" --intf dummy \
        --extraintf=oldrc --rc-unix="$snap_dir/vlc-$port.sock" --rc-fake-tty \
        --snapshot-path="$snap_dir" --snapshot-prefix="lc$port-" --snapshot-format=jpg --snapshot-sequential \
        --no-mouse-events "${extra[@]}" $(screen_vlc_args "$screen") "$mrl" >/dev/null 2>&1 < /dev/null &
    vlc_pid=$!
}

vlc_pid=""
up=0
trap '[ -n "$vlc_pid" ] && kill "$vlc_pid" 2>/dev/null; exit 0' INT TERM HUP
while :; do
    if [ "$kind" = usb ] && [ ! -e "$dev" ]; then
        [ -n "$vlc_pid" ] && { kill "$vlc_pid" 2>/dev/null; vlc_pid=""; }
        [ "$up" = 1 ] && { notify "Tela $n desconectada ($label)"; up=0; }
        sleep 2
        continue
    fi
    if [ -z "$vlc_pid" ] || ! kill -0 "$vlc_pid" 2>/dev/null; then
        start_vlc
        sleep 2
    fi
    if [ "$kind" = usb ]; then now=1; else now=$(rc_playing); fi
    if [ "$now" = 1 ] && [ "$up" = 0 ]; then up=1; notify "Tela $n conectada ($label)"; fi
    if [ "$now" != 1 ] && [ "$up" = 1 ]; then up=0; notify "Tela $n desconectada ($label)"; fi
    sleep 1
done
