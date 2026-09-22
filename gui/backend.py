#!/usr/bin/env python3
"""LazyCast GUI - camada de dados (sem GTK, testável sem hardware).

Lê o estado do sistema (serviço, grupo Wi-Fi Direct, aparelhos conectados, receptores),
lê/grava lazycast-config.conf e monta o relatório de saúde. Todas as chamadas a comandos
passam por `run()`, que os testes substituem.
"""
import os
import re
import subprocess

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(APP_DIR, 'lazycast-config.conf')
LEASES_PATH = os.path.join(APP_DIR, 'udhcpd.leases')
LOG_PATH = '/var/log/lazycast/lazycast-background.log'
LABWC_RC = os.path.join(os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'labwc', 'rc.xml')
SERVICE = 'lazycast'

DEFAULTS = {
    'DISPLAY_MODE': '1',
    'SCREEN1_SOURCE': 'auto',
    'SCREEN2_SOURCE': 'auto',
    'DISPLAY1_NAME': 'raspberry',
    'LAZYCAST_AUTH': 'pbc',
    'LAZYCAST_PIN': '',
    'DISABLE_1920_1080_60FPS': '1',
    'ENABLE_MOUSE_KEYBOARD': '0',
    'DISPLAY1_DHCP_START': '192.168.173.80',
    'DISPLAY1_RTP_PORT': '1028',
    'DISPLAY2_RTP_PORT': '1030',
}


def run(cmd, timeout=6):
    """Executa um comando (lista) e devolve (código, saída). Nunca levanta exceção."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or '') + (p.stderr or '')
    except (OSError, subprocess.SubprocessError) as e:
        return 127, str(e)


def sudo(cmd, timeout=8):
    return run(['sudo', '-n'] + cmd, timeout)


# ------------------------------------------------------------------ configuração
def parse_config(text):
    """KEY="valor" ou KEY=valor (ignora comentários) -> dict."""
    cfg = {}
    for line in text.splitlines():
        m = re.match(r'^\s*([A-Z0-9_]+)=(.*)$', line)
        if m:
            cfg[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return cfg


def load_config(path=None):
    path = path or CONFIG_PATH
    cfg = dict(DEFAULTS)
    try:
        with open(path, encoding='utf-8') as f:
            cfg.update(parse_config(f.read()))
    except OSError:
        pass
    return cfg


def update_config_text(text, updates):
    """Atualiza chaves preservando comentários e ordem; chaves novas vão para o fim."""
    remaining = dict(updates)
    out = []
    for line in text.splitlines():
        m = re.match(r'^(\s*)([A-Z0-9_]+)=(.*)$', line)
        if m and m.group(2) in remaining:
            key = m.group(2)
            out.append('%s%s="%s"' % (m.group(1), key, remaining.pop(key)))
        else:
            out.append(line)
    for key, val in remaining.items():
        out.append('%s="%s"' % (key, val))
    return '\n'.join(out) + '\n'


def save_config(updates, path=None):
    path = path or CONFIG_PATH
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read()
    except OSError:
        text = ''
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(update_config_text(text, updates))


# ------------------------------------------------------------------ nome do display
def valid_display_name(name):
    """Nome que aparece no Windows/Android: 1 a 32 caracteres (limite do Wi-Fi Direct). Só letras, números,
    espaço, ponto, hífen e sublinhado: o lazycast-config.conf é lido pelo shell (`source`), então aspas,
    $ e crases não podem entrar."""
    return bool(re.fullmatch(r"[A-Za-z0-9 ._-]{1,32}", (name or '').strip()))


# ------------------------------------------------------------------ PIN WPS
def wps_checksum_ok(pin):
    """PIN WPS de 8 dígitos com dígito verificador válido."""
    if not re.fullmatch(r'[0-9]{8}', pin or ''):
        return False
    acc = sum((3 if i % 2 == 0 else 1) * int(d) for i, d in enumerate(pin))
    return acc % 10 == 0


def generate_pin(rand=None):
    import random
    r = rand or random
    n = r.randint(1000000, 9999999)
    acc = sum((3 if i % 2 == 0 else 1) * int(d) for i, d in enumerate(str(n)))
    return '%d%d' % (n, (10 - acc % 10) % 10)


# ------------------------------------------------------------------ estado
def service_state():
    code, out = run(['systemctl', 'is-active', SERVICE])
    return out.strip().splitlines()[0] if out.strip() else 'unknown'


def service_enabled():
    code, out = run(['systemctl', 'is-enabled', SERVICE])
    return out.strip() == 'enabled'


def group_interface():
    """Interface do grupo P2P (p2p-wlan0-N) ou None."""
    code, out = run(['iw', 'dev'])
    m = re.search(r'Interface\s+(p2p-wl\S+)', out)
    return m.group(1) if m else None


def parse_stations(text):
    return re.findall(r'^Station\s+([0-9a-f:]{17})', text, re.M | re.I)


def parse_leases(text):
    """Saída de `busybox dumpleases` -> {mac: (ip, hostname)}."""
    leases = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and re.fullmatch(r'[0-9a-f:]{17}', parts[0], re.I):
            leases[parts[0].lower()] = (parts[1], parts[2] if not parts[2][0].isdigit() else '')
    return leases


def slot_ip(cfg, slot):
    base = cfg.get('DISPLAY1_DHCP_START', DEFAULTS['DISPLAY1_DHCP_START'])
    head, _, last = base.rpartition('.')
    try:
        return '%s.%d' % (head, int(last) + slot)
    except ValueError:
        return base


def slot_streaming(port):
    """Há um receptor (VLC ou a prévia do ffmpeg) rodando neste canal?"""
    # o canal de snapshot lc<porta>- aparece na linha de comando do VLC (Miracast/USB/rede) e do ffmpeg (prévia)
    code, out = run(['pgrep', '-f', 'lc%s-' % port])
    return code == 0


# ------------------------------------------------------------------ fontes de cada tela
def screen_source(cfg, k):
    """Fonte da tela k (0-based): auto|wireless, usb:<by-id> ou stream:<porta>."""
    return (cfg.get('SCREEN%d_SOURCE' % (k + 1)) or 'auto').strip()


def parse_source(src):
    """-> ('wireless', None) | ('usb', id) | ('stream', porta). Valores inválidos viram sem fio."""
    if src.startswith('usb:') and len(src) > 4:
        return 'usb', src[4:]
    m = re.fullmatch(r'stream:([0-9]{2,5})', src)
    if m:
        return 'stream', m.group(1)
    return 'wireless', None


def wireless_screens(cfg, n):
    return [k for k in range(n) if parse_source(screen_source(cfg, k))[0] == 'wireless']


def rtp_port(cfg, k):
    """Porta que identifica o canal (snapshot lc<porta>-) da tela k."""
    return cfg.get('DISPLAY%d_RTP_PORT' % (k + 1)) or str(1028 + 2 * k)


def default_stream_port(k):
    return 5004 + 2 * k


def friendly_usb_name(byid):
    """usb-MACROSILICON_USB_Video-video-index0 -> MACROSILICON USB Video"""
    n = re.sub(r'^usb-', '', byid)
    n = re.sub(r'-video-index\d+$', '', n)
    n = re.sub(r'-\d+$', '', n)
    return n.replace('_', ' ').strip() or byid


def list_usb_video(base='/dev/v4l/by-id'):
    """Entradas de vídeo USB (capturadoras UVC, webcams) em QUALQUER porta USB: [{id, name}]."""
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return []
    return [dict(id=n, name=friendly_usb_name(n)) for n in names if n.endswith('-video-index0')]


def source_options(k, cfg=None, usb=None):
    """Opções do seletor de fonte da tela k: [(valor, rótulo)]. Inclui a fonte atual mesmo se ausente."""
    cfg = cfg or load_config()
    usb = list_usb_video() if usb is None else usb
    opts = [('auto', 'Sem fio (Miracast)'),
            ('stream:%d' % default_stream_port(k), 'Tela estendida do Windows (rede, porta %d)' % default_stream_port(k))]
    for u in usb:
        opts.append(('usb:' + u['id'], 'Entrada USB: ' + u['name']))
    cur = screen_source(cfg, k)
    if cur not in [v for v, _ in opts]:
        kind, val = parse_source(cur)
        if kind == 'usb':
            opts.append((cur, 'Entrada USB: %s (desconectada)' % friendly_usb_name(val)))
        elif kind == 'stream':
            opts.append((cur, 'Tela estendida do Windows (rede, porta %s)' % val))
    return opts


def pi_address():
    """IP do Pi na rede (para informar ao Windows)."""
    code, out = run(['hostname', '-I'])
    ips = [i for i in out.split() if re.fullmatch(r'[0-9]{1,3}(\.[0-9]{1,3}){3}', i)]
    return next((i for i in ips if not i.startswith('192.168.173.') and not i.startswith('192.168.174.')), ips[0] if ips else '')


def pi_addresses():
    """[(rótulo, ip)] das interfaces do Pi na rede (cabo e Wi-Fi), sem as redes internas do Wi-Fi Direct.
    O Windows pode enviar a tela estendida por qualquer uma delas."""
    code, out = run(['ip', '-4', '-o', 'addr', 'show'])
    found = []
    for line in out.splitlines():
        m = re.match(r'\d+:\s+(\S+)\s+inet\s+([0-9.]+)/', line)
        if not m:
            continue
        iface, ip = m.groups()
        if iface == 'lo' or iface.startswith('p2p-') or ip.startswith(('192.168.173.', '192.168.174.', '127.')):
            continue
        found.append(('Cabo' if iface.startswith(('eth', 'en')) else 'Wi-Fi', ip))
    return sorted(found, key=lambda x: x[0] != 'Cabo')


def stream_alive(port):
    """Fluxo de rede recebendo: quadro de prévia recente (ffmpeg, sem monitor) ou VLC tocando (com monitor)."""
    if latest_frame(snap_dir(), port):
        return True
    return rc_is_playing(port)


def rc_is_playing(port, directory=None):
    import socket
    sock_path = os.path.join(directory or snap_dir(), 'vlc-%s.sock' % port)
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(1.0)
        s.connect(sock_path)
        s.sendall(b'is_playing\n')
        data = s.recv(200).decode(errors='replace')
        s.close()
        m = re.search(r'\b([01])\b', data)
        return bool(m and m.group(1) == '1')
    except (OSError, AttributeError):
        return False


def _blank_slot(k, kind, label, ip=''):
    return dict(index=k, kind=kind, label=label, ip=ip, connected=False, streaming=False, source='')


def get_status(cfg=None):
    cfg = cfg or load_config()
    try:
        nscreens = max(1, min(2, int(cfg.get('DISPLAY_MODE', '1'))))
    except ValueError:
        nscreens = 1
    kinds = [parse_source(screen_source(cfg, k)) for k in range(nscreens)]
    wl = wireless_screens(cfg, nscreens)
    st = {
        'service': service_state(),
        'name': cfg.get('DISPLAY1_NAME', 'raspberry'),
        'mode': nscreens,
        'auth': cfg.get('LAZYCAST_AUTH', 'pbc'),
        'group': None,
        'stations': [],
        'slots': [],
        'wired_only': len(wl) == 0,
    }

    def slot_for(k, conns):
        kind, val = kinds[k]
        port = rtp_port(cfg, k)
        if kind == 'usb':
            present = os.path.exists('/dev/v4l/by-id/' + val)
            s = _blank_slot(k, 'usb', 'Entrada USB: ' + friendly_usb_name(val))
            s.update(connected=present, streaming=present and slot_streaming(port),
                     source=friendly_usb_name(val) if present else '')
            return s
        if kind == 'stream':
            alive = st['service'] == 'active' and stream_alive(port)
            s = _blank_slot(k, 'stream', 'Tela estendida (rede, porta %s)' % val)
            s.update(connected=alive, streaming=alive, source='Windows (rede)' if alive else '')
            return s
        j = wl.index(k)
        ip = slot_ip(cfg, j)
        who = next((c for c in conns if c['ip'] == ip), None)
        s = _blank_slot(k, 'wireless', 'Sem fio (Miracast)', ip)
        s.update(connected=who is not None, streaming=who is not None and slot_streaming(port),
                 source=(who['host'] or who['mac']) if who else '')
        return s

    if st['service'] != 'active':
        st['state'] = 'stopped' if st['service'] in ('inactive', 'unknown') else 'error'
        st['slots'] = [slot_for(k, []) for k in range(nscreens)]
        return st
    conns = []
    if wl:
        g = group_interface()
        st['group'] = g
        if not g:
            st['state'] = 'starting'
            st['slots'] = [slot_for(k, []) for k in range(nscreens)]
            return st
        code, out = run(['iw', 'dev', g, 'station', 'dump'])
        macs = parse_stations(out)
        code, lout = sudo(['busybox', 'dumpleases', '-f', LEASES_PATH])
        leases = parse_leases(lout)
        for mac in macs:
            ip, host = leases.get(mac.lower(), ('', ''))
            conns.append(dict(mac=mac, ip=ip, host=host))
        st['stations'] = conns
    st['slots'] = [slot_for(k, conns) for k in range(nscreens)]
    st['state'] = 'connected' if (conns or any(s['connected'] and s['kind'] != 'wireless' for s in st['slots'])) else 'ready'
    return st


# ------------------------------------------------------------------ saúde
def health_checks(cfg=None):
    """Lista de (rótulo, ok, dica). Só informação de leitura."""
    cfg = cfg or load_config()
    checks = []
    svc = service_state()
    checks.append(('Serviço LazyCast', svc == 'active',
                   'Parado. Use o botão Iniciar na aba Início.' if svc != 'active' else ''))
    try:
        nscreens = max(1, min(2, int(cfg.get('DISPLAY_MODE', '1'))))
    except ValueError:
        nscreens = 1
    for k in range(nscreens):
        kind, val = parse_source(screen_source(cfg, k))
        if kind == 'usb':
            ok = os.path.exists('/dev/v4l/by-id/' + val)
            checks.append(('Tela %d: entrada USB (%s)' % (k + 1, friendly_usb_name(val)), ok,
                           '' if ok else 'A capturadora não está conectada a nenhuma porta USB.'))
        elif kind == 'stream':
            ok = stream_alive(rtp_port(cfg, k))
            checks.append(('Tela %d: fluxo de rede (porta %s)' % (k + 1, val), ok,
                           '' if ok else 'Nada chegando. No Windows, abra o LazyCast.exe (ou LazyCast.bat) e clique em Conectar/Ligar tela virtual (IP do Pi: %s).' % (pi_address() or '?')))
    if not wireless_screens(cfg, nscreens):
        return checks
    code, out = sudo(['wpa_cli', 'interface'])
    has_p2p = 'p2p-dev-' in out
    checks.append(('Wi-Fi Direct (P2P) disponível', has_p2p,
                   'O Wi-Fi do Pi não expõe o P2P. Veja o README (NetworkManager).' if not has_p2p else ''))
    g = group_interface()
    checks.append(('Rede do display criada', bool(g),
                   'O grupo Wi-Fi Direct ainda não foi criado; aguarde ou reinicie.' if not g else ''))
    code, out = sudo(['wpa_cli', '-i', 'p2p-dev-wlan0', 'get', 'wifi_display'])
    wfd = out.strip().splitlines()[-1:] == ['1']
    checks.append(('Anúncio Miracast (WFD) ligado', wfd,
                   'Sem isso o Windows/Android não listam o display. Reinicie o serviço.' if not wfd else ''))
    code, out = run(['pgrep', '-f', 'udhcpd'])
    checks.append(('Servidor de IP (DHCP)', code == 0, 'Reinicie o serviço.' if code != 0 else ''))
    code, out = run(['pgrep', '-f', 'd2.py'])
    checks.append(('Receptor Miracast (d2.py)', code == 0, 'Reinicie o serviço.' if code != 0 else ''))
    code, out = run(['ps', '-o', 'stat=', '-C', 'NetworkManager'])
    paused = out.strip().startswith('T')
    checks.append(('NetworkManager pausado durante o uso', paused or code != 0,
                   'Ele derruba o grupo Wi-Fi Direct; o serviço deveria pausá-lo.' if not (paused or code != 0) else ''))
    return checks


def read_log(lines=200):
    try:
        with open(LOG_PATH, encoding='utf-8', errors='replace') as f:
            return ''.join(f.readlines()[-lines:])
    except OSError as e:
        return 'Não foi possível ler o log (%s): %s' % (LOG_PATH, e)


def report_text(cfg=None):
    cfg = cfg or load_config()
    lines = ['LazyCast - relatório', '']
    for label, ok, hint in health_checks(cfg):
        lines.append('[%s] %s%s' % ('OK' if ok else 'FALHA', label, (' - ' + hint) if hint else ''))
    lines += ['', 'Configuração:']
    for k in ('DISPLAY_MODE', 'DISPLAY1_NAME', 'LAZYCAST_AUTH', 'DISABLE_1920_1080_60FPS', 'ENABLE_MOUSE_KEYBOARD'):
        lines.append('  %s=%s' % (k, cfg.get(k, '')))
    lines += ['', 'Log (últimas linhas):', read_log(40)]
    return '\n'.join(lines)


# ------------------------------------------------------------------ prévia (snapshot do VLC)
def snap_dir():
    """Pasta privada do usuário onde o receptor (d2.py) cria o socket e os snapshots do VLC."""
    return os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'lazycast')


def latest_snapshot(directory, port):
    """Devolve os bytes do snapshot mais recente da porta e apaga os antigos (evita acumular)."""
    import glob
    files = sorted(glob.glob(os.path.join(directory, 'lc%s-*.jpg' % port)), key=os.path.getmtime)
    if not files:
        return None
    try:
        with open(files[-1], 'rb') as f:
            data = f.read()
    except OSError:
        return None
    for old in files:
        try:
            os.remove(old)
        except OSError:
            pass
    return data or None


def latest_frame(directory, port, max_age=6.0):
    """Quadro de prévia gravado pelo ffmpeg do Pi (lc<porta>-latest.jpg) se for recente; senão None.
    Usado no modo sem monitor com fluxo de rede (o VLC sem janela não entrega snapshots de forma confiável)."""
    import time
    path = os.path.join(directory, 'lc%s-latest.jpg' % port)
    try:
        if time.time() - os.path.getmtime(path) > max_age:
            return None
        with open(path, 'rb') as f:
            return f.read() or None
    except OSError:
        return None


def request_snapshot(port, wait=1.2, directory=None):
    """Pede um snapshot ao VLC daquela porta (socket RC) e devolve os bytes JPEG, ou None."""
    import socket
    import time
    directory = directory or snap_dir()
    frame = latest_frame(directory, port)
    if frame:
        return frame
    sock_path = os.path.join(directory, 'vlc-%s.sock' % port)
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(1.5)
        s.connect(sock_path)
        s.sendall(b'snapshot\n')
        s.close()
    except (OSError, AttributeError):
        return None
    deadline = time.time() + wait
    while time.time() < deadline:
        data = latest_snapshot(directory, port)
        if data:
            return data
        time.sleep(0.1)
    return None


# ------------------------------------------------------------------ ações
def service_action(action):
    """start|stop|restart|enable|disable. Devolve (ok, mensagem)."""
    code, out = sudo(['systemctl', action, SERVICE], timeout=40)
    return code == 0, out.strip()
