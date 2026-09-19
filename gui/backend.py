#!/usr/bin/env python3
"""LazyCast GUI - camada de dados (sem GTK, testável sem hardware).

Lê o estado do sistema (serviço, grupo Wi-Fi Direct, aparelhos conectados, receptores),
lê/grava lazycast-config.conf e monta o relatório de saúde. Todas as chamadas a comandos
passam por `run()`, que os testes substituem.
"""
import os
import re
import shlex
import subprocess

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(APP_DIR, 'lazycast-config.conf')
LEASES_PATH = os.path.join(APP_DIR, 'udhcpd.leases')
LOG_PATH = '/var/log/lazycast/lazycast-background.log'
LABWC_RC = os.path.join(os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'labwc', 'rc.xml')
SERVICE = 'lazycast'

DEFAULTS = {
    'DISPLAY_MODE': '1',
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
    """Há VLC recebendo nesta porta RTP?"""
    code, out = run(['pgrep', '-f', 'rtp://0.0.0.0:%s' % port])
    return code == 0


def get_status(cfg=None):
    cfg = cfg or load_config()
    nscreens = 2 if cfg.get('DISPLAY_MODE') == '2' else 1
    st = {
        'service': service_state(),
        'name': cfg.get('DISPLAY1_NAME', 'raspberry'),
        'mode': nscreens,
        'auth': cfg.get('LAZYCAST_AUTH', 'pbc'),
        'group': None,
        'stations': [],
        'slots': [],
    }
    if st['service'] != 'active':
        st['state'] = 'stopped' if st['service'] in ('inactive', 'unknown') else 'error'
        st['slots'] = [dict(index=i, ip=slot_ip(cfg, i), connected=False, streaming=False, source='')
                       for i in range(nscreens)]
        return st
    g = group_interface()
    st['group'] = g
    if not g:
        st['state'] = 'starting'
        st['slots'] = [dict(index=i, ip=slot_ip(cfg, i), connected=False, streaming=False, source='')
                       for i in range(nscreens)]
        return st
    code, out = run(['iw', 'dev', g, 'station', 'dump'])
    macs = parse_stations(out)
    code, lout = sudo(['busybox', 'dumpleases', '-f', LEASES_PATH])
    leases = parse_leases(lout)
    conns = []
    for mac in macs:
        ip, host = leases.get(mac.lower(), ('', ''))
        conns.append(dict(mac=mac, ip=ip, host=host))
    st['stations'] = conns
    ports = [cfg.get('DISPLAY1_RTP_PORT', '1028'), cfg.get('DISPLAY2_RTP_PORT', '1030')]
    for i in range(nscreens):
        ip = slot_ip(cfg, i)
        who = next((c for c in conns if c['ip'] == ip), None)
        st['slots'].append(dict(index=i, ip=ip, connected=who is not None,
                                streaming=slot_streaming(ports[i]),
                                source=(who['host'] or who['mac']) if who else ''))
    st['state'] = 'connected' if conns else 'ready'
    return st


# ------------------------------------------------------------------ saúde
def health_checks(cfg=None):
    """Lista de (rótulo, ok, dica). Só informação de leitura."""
    cfg = cfg or load_config()
    checks = []
    svc = service_state()
    checks.append(('Serviço LazyCast', svc == 'active',
                   'Parado. Use o botão Iniciar na aba Início.' if svc != 'active' else ''))
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


# ------------------------------------------------------------------ prévia (grim)
def layout_regions(rc_path=None, n=2):
    """Lê as regras de layout do LazyCast (rc.xml) e devolve, por tela, os argumentos do grim:
    região 'x,y WxH' (lado a lado) ou saída (-o HDMI-A-1)."""
    rc_path = rc_path or LABWC_RC
    try:
        with open(rc_path, encoding='utf-8') as f:
            xml = f.read()
    except OSError:
        return []
    if 'lazycast-layout' not in xml:
        return []
    regs = []
    for i in range(1, n + 1):
        m = re.search(r'title="LazyCast-%d">(.*?)</windowRule>' % i, xml, re.S)
        if not m:
            break
        body = m.group(1)
        out = re.search(r'name="MoveToOutput" output="([^"]+)"', body)
        pos = re.search(r'name="MoveTo" x="(-?\d+)" y="(-?\d+)"', body)
        size = re.search(r'name="ResizeTo" width="(\d+)" height="(\d+)"', body)
        if out:
            regs.append(['-o', out.group(1)])
        elif pos and size:
            regs.append(['-g', '%s,%s %sx%s' % (pos.group(1), pos.group(2), size.group(1), size.group(2))])
        else:
            break
    return regs


def grab(grim_args, timeout=4):
    """Captura via grim (PPM) e devolve bytes ou None."""
    env = dict(os.environ)
    env.setdefault('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid())
    env.setdefault('WAYLAND_DISPLAY', 'wayland-0')
    try:
        p = subprocess.run(['grim', '-t', 'ppm'] + grim_args + ['-'], capture_output=True, timeout=timeout, env=env)
        return p.stdout if p.returncode == 0 and p.stdout else None
    except (OSError, subprocess.SubprocessError):
        return None


# ------------------------------------------------------------------ ações
def service_action(action):
    """start|stop|restart|enable|disable. Devolve (ok, mensagem)."""
    code, out = sudo(['systemctl', action, SERVICE], timeout=40)
    return code == 0, out.strip()
