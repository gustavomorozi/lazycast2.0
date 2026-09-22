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
title_fundo="LazyCast-Fundo-$n"
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
        # Com buffer de 60-150 ms o VLC descarta os quadros ("picture is too late", PCR atrasado) e a prévia
        # nunca recebe imagem; 300 ms funcionou no Pi 5 (testado com ffmpeg/QuickSync no Windows).
        # Ajustável: LAZYCAST_STREAM_CACHING=<ms> (menor = menos latência, mais risco de perder quadros).
        # --no-audio: o fluxo de tela não tem áudio; sem isso o VLC espera o relógio de um áudio inexistente e
        # não exibe o vídeo (o snapshot da prévia nunca sai). Testado no Pi 5.
        extra=(--no-audio --network-caching=${LAZYCAST_STREAM_CACHING:-300} --live-caching=${LAZYCAST_STREAM_CACHING:-300})
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

# --no-mouse-events só com janela: com --vout=dummy ele impede o VLC de exibir quadros e o snapshot da prévia
# nunca sai (testado no Pi 5).
mouse_args=(--no-mouse-events)
[ "$LAZYCAST_VLC_MODE" = "hidden" ] && mouse_args=()

# Fundo permanente: enquanto não chega fluxo (ou se ele cair), o monitor não fica preto/sem sinal — mostra
# "Tela N aguardando conexão". É uma janela própria (mesmo título fixo LazyCast-Fundo-N, sempre no mesmo
# conector), colocada no fundo pela regra do labwc (ToggleAlwaysOnBottom); quando o vídeo real aparece, ele
# cobre o fundo por cima. Só faz sentido com monitor de verdade (LAZYCAST_VLC_MODE=window).
idle_png="$snap_dir/lc-fundo-$n.png"
idle_pid=""
gerar_fundo() {
    local fonte=/usr/share/fonts/truetype/dejavu
    ffmpeg -y -f lavfi -i color=c=0x1e1e1e:s=1920x1080 -frames:v 1 -update 1 -vf \
        "drawtext=fontfile=$fonte/DejaVuSans-Bold.ttf:text=Tela $n:fontcolor=white:fontsize=96:x=(w-text_w)/2:y=(h-text_h)/2-40,drawtext=fontfile=$fonte/DejaVuSans.ttf:text=aguardando conexao:fontcolor=0xaaaaaa:fontsize=40:x=(w-text_w)/2:y=(h-text_h)/2+70" \
        "$idle_png" >/dev/null 2>&1
}
start_idle() {
    [ "$LAZYCAST_VLC_MODE" = "hidden" ] && return
    [ -f "$idle_png" ] || gerar_fundo
    [ -f "$idle_png" ] || return
    vlc --fullscreen --video-title="$title_fundo" --intf dummy --no-audio --image-duration=-1 \
        --no-mouse-events "$idle_png" >/dev/null 2>&1 < /dev/null &
    idle_pid=$!
}

# Sem monitor (hidden) e fluxo de rede: o VLC com --vout=dummy exibe quadros de forma intermitente
# ("buffer deadlock prevented") e o snapshot da prévia falha. Nesse caso o ffmpeg do Pi decodifica o fluxo
# e grava 1 quadro por segundo em lc<porta>-latest.jpg, que o painel lê (independe de janela e de relógio).
use_ffmpeg_preview=0
if [ "$LAZYCAST_VLC_MODE" = "hidden" ] && [ "$kind" = stream ] && command -v ffmpeg >/dev/null 2>&1; then
    use_ffmpeg_preview=1
fi
preview_file="$snap_dir/lc$port-latest.jpg"

start_ffmpeg_preview() {
    ffmpeg -nostdin -hide_banner -loglevel error -fflags nobuffer -flags low_delay \
        -probesize 500000 -analyzeduration 500000 \
        -i "udp://0.0.0.0:$udp_port?fifo_size=2000000&overrun_nonfatal=1&timeout=5000000" \
        -an -vf "fps=1,scale=960:-2" -q:v 6 -f image2 -update 1 -atomic_writing 1 -y "$preview_file" \
        >/dev/null 2>&1 < /dev/null &
    vlc_pid=$!
}

# 1 se o quadro de prévia é recente (fluxo chegando); usado para "conectada/desconectada"
frame_fresh() {
    [ -f "$preview_file" ] && [ $(( $(date +%s) - $(stat -c %Y "$preview_file") )) -le 4 ] && echo 1 || echo 0
}

start_vlc() {
    vlc "${vlc_mode_args[@]}" --video-title="$title" --intf dummy \
        --extraintf=oldrc --rc-unix="$snap_dir/vlc-$port.sock" --rc-fake-tty \
        --snapshot-path="$snap_dir" --snapshot-prefix="lc$port-" --snapshot-format=jpg --snapshot-sequential \
        "${mouse_args[@]}" "${extra[@]}" $(screen_vlc_args "$screen") "$mrl" >/dev/null 2>&1 < /dev/null &
    vlc_pid=$!
}

vlc_pid=""
up=0
trap '[ -n "$vlc_pid" ] && kill "$vlc_pid" 2>/dev/null; [ -n "$idle_pid" ] && kill "$idle_pid" 2>/dev/null; exit 0' INT TERM HUP
start_idle
while :; do
    [ -n "$idle_pid" ] && ! kill -0 "$idle_pid" 2>/dev/null && start_idle
    if [ "$kind" = usb ] && [ ! -e "$dev" ]; then
        [ -n "$vlc_pid" ] && { kill "$vlc_pid" 2>/dev/null; vlc_pid=""; }
        [ "$up" = 1 ] && { notify "Tela $n desconectada ($label)"; up=0; }
        sleep 2
        continue
    fi
    if [ -z "$vlc_pid" ] || ! kill -0 "$vlc_pid" 2>/dev/null; then
        if [ "$use_ffmpeg_preview" = 1 ]; then start_ffmpeg_preview; else start_vlc; fi
        sleep 2
    fi
    if [ "$kind" = usb ]; then now=1; elif [ "$use_ffmpeg_preview" = 1 ]; then now=$(frame_fresh); else now=$(rc_playing); fi
    if [ "$now" = 1 ] && [ "$up" = 0 ]; then up=1; notify "Tela $n conectada ($label)"; fi
    if [ "$now" != 1 ] && [ "$up" = 1 ]; then up=0; notify "Tela $n desconectada ($label)"; fi
    sleep 1
done
