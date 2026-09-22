"""LazyCast para Windows - reescrita em Python (era PowerShell).

Janela unica para:
  * ligar/desligar as telas virtuais e envia-las ao Raspberry Pi pela rede (cabo ou Wi-Fi);
  * instalar/desinstalar o driver de monitor virtual (Virtual Display Driver, projeto VirtualDrivers);
  * conectar ao Pi por Miracast (o "Transmitir" do Windows).

Compilado com PyInstaller em um .exe proprio (LazyCast.exe): resolve o pedido de nao aparecer mais
"powershell.exe" no Gerenciador de Tarefas. So usa a biblioteca padrao do Python + pystray/Pillow
(icone da bandeja) - nada de PowerShell nem de instalar nada a mais no Windows.
"""
import concurrent.futures
import ctypes
import ctypes.wintypes as wt
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import tkinter as tk
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from tkinter import messagebox, ttk

PASTA = Path(sys.argv[0]).resolve().parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent
IP_FILE = PASTA / 'pi-ip.txt'
NOME_FILE = PASTA / 'miracast-nome.txt'
PID_FILE = PASTA / 'estender.pids'
LOG_FILE = PASTA / 'estender-log.txt'
CFG_VDD = Path(r'C:\VirtualDisplayDriver\vdd_settings.xml')
DRV_URL = 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/25.7.23/VDD.Control.25.7.23.zip'
DRV_SHA256 = 'a701f2272e9fcf382849b24f913c6dd07597b3b1116525f2e90182f019609154'
DRV_PASTA = Path(os.environ['LOCALAPPDATA']) / 'LazyCast' / 'driver'

CREATE_NO_WINDOW = 0x08000000

# ============================================================ Win32: telas virtuais (ctypes)
user32 = ctypes.windll.user32


class DISPLAY_DEVICE(ctypes.Structure):
    _fields_ = [
        ('cb', wt.DWORD), ('DeviceName', wt.WCHAR * 32), ('DeviceString', wt.WCHAR * 128),
        ('StateFlags', wt.DWORD), ('DeviceID', wt.WCHAR * 128), ('DeviceKey', wt.WCHAR * 128),
    ]


class DEVMODE(ctypes.Structure):
    _fields_ = [
        ('dmDeviceName', wt.WCHAR * 32), ('dmSpecVersion', wt.WORD), ('dmDriverVersion', wt.WORD),
        ('dmSize', wt.WORD), ('dmDriverExtra', wt.WORD), ('dmFields', wt.DWORD),
        ('dmPositionX', wt.LONG), ('dmPositionY', wt.LONG), ('dmDisplayOrientation', wt.DWORD),
        ('dmDisplayFixedOutput', wt.DWORD), ('dmColor', wt.SHORT), ('dmDuplex', wt.SHORT),
        ('dmYResolution', wt.SHORT), ('dmTTOption', wt.SHORT), ('dmCollate', wt.SHORT),
        ('dmFormName', wt.WCHAR * 32), ('dmLogPixels', wt.WORD), ('dmBitsPerPel', wt.DWORD),
        ('dmPelsWidth', wt.DWORD), ('dmPelsHeight', wt.DWORD), ('dmDisplayFlags', wt.DWORD),
        ('dmDisplayFrequency', wt.DWORD), ('dmICMMethod', wt.DWORD), ('dmICMIntent', wt.DWORD),
        ('dmMediaType', wt.DWORD), ('dmDitherType', wt.DWORD), ('dmReserved1', wt.DWORD),
        ('dmReserved2', wt.DWORD), ('dmPanningWidth', wt.DWORD), ('dmPanningHeight', wt.DWORD),
    ]


DISPLAY_DEVICE_ATTACHED = 0x1
CDS_UPDATEREGISTRY = 0x1
CDS_NORESET = 0x10000000
DISP_CHANGE_SUCCESSFUL = 0
SDC_APPLY = 0x80
SDC_TOPOLOGY_EXTEND = 0x4
DM_POSITION = 0x20
DM_PELSWIDTH = 0x80000
DM_PELSHEIGHT = 0x100000
DM_DISPLAYFREQUENCY = 0x400000


def novo_devmode():
    dm = DEVMODE()
    dm.dmSize = ctypes.sizeof(DEVMODE)
    return dm


def get_telas_virtuais():
    """[(nome, anexado)] dos monitores do Virtual Display Driver (independente de estarem na area de trabalho)."""
    r = []
    i = 0
    while True:
        d = DISPLAY_DEVICE()
        d.cb = ctypes.sizeof(d)
        if not user32.EnumDisplayDevicesW(None, i, ctypes.byref(d), 0):
            break
        if d.DeviceString == 'Virtual Display Driver':
            r.append((d.DeviceName, bool(d.StateFlags & DISPLAY_DEVICE_ATTACHED)))
        i += 1
    return r


def estender_topologia():
    # Equivale a Win+P > Estender (SDC_APPLY | SDC_TOPOLOGY_EXTEND): unico jeito confiavel de anexar
    # monitor virtual novo/nunca usado; o Windows os posiciona lado a lado a direita da tela principal.
    return user32.SetDisplayConfig(0, None, 0, None, SDC_APPLY | SDC_TOPOLOGY_EXTEND)


def desanexar_telas_virtuais():
    """Solta da area de trabalho (o monitor continua existindo no driver). Devolve quantas soltou."""
    n = 0
    for nome, anexado in get_telas_virtuais():
        if not anexado:
            continue
        dm = novo_devmode()
        dm.dmFields = DM_POSITION | DM_PELSWIDTH | DM_PELSHEIGHT
        dm.dmPelsWidth = 0
        dm.dmPelsHeight = 0
        rc = user32.ChangeDisplaySettingsExW(nome, ctypes.byref(dm), None, CDS_UPDATEREGISTRY | CDS_NORESET, None)
        if rc == DISP_CHANGE_SUCCESSFUL:
            n += 1
    if n:
        user32.ChangeDisplaySettingsExW(None, None, None, 0, None)
    time.sleep(2)
    return n


def anexar_telas_virtuais(maximo=2, w=1920, h=1080, hz=60, log=None):
    """Anexa ate `maximo` monitores virtuais e deixa cada um em w x h @ hz. Devolve quantos ficaram ativos.

    1) Estender (SetDisplayConfig, como Win+P): unico jeito confiavel de anexar monitor virtual novo/nunca usado.
    2) Modo: ChangeDisplaySettingsEx com flags 0 (mudanca dinamica). Com CDS_UPDATEREGISTRY/NORESET o driver
       recusa (codigo -1) e a aplicacao chega a soltar as telas; com flags 0 funciona (testado com o driver 25.7.23).
    """
    def ativas():
        return sum(1 for _, a in get_telas_virtuais() if a)

    existem = len(get_telas_virtuais())
    if ativas() < min(maximo, existem):
        estender_topologia()
        for _ in range(8):
            if ativas() >= min(maximo, existem):
                break
            time.sleep(0.7)

    alvo = []
    for nome, anexado in get_telas_virtuais():
        if not anexado or len(alvo) >= maximo:
            continue
        dm = novo_devmode()
        user32.EnumDisplaySettingsW(nome, -1, ctypes.byref(dm))
        alvo.append((nome, dm.dmPositionX, dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency))
    alvo.sort(key=lambda t: t[1], reverse=True)  # a mais a direita primeiro (aumenta sem sobrepor a vizinha)

    for nome, x, tw, th, thz in alvo:
        if (tw, th, thz) == (w, h, hz):
            continue
        dm = novo_devmode()
        user32.EnumDisplaySettingsW(nome, -1, ctypes.byref(dm))
        dm.dmPelsWidth = w
        dm.dmPelsHeight = h
        dm.dmDisplayFrequency = hz
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY
        rc = user32.ChangeDisplaySettingsExW(nome, ctypes.byref(dm), None, 0, None)
        if rc != DISP_CHANGE_SUCCESSFUL and log:
            log(f'Aviso: {nome} nao aceitou {w}x{h}@{hz} (codigo {rc}).')
        time.sleep(0.8)
    return ativas()


def modo_real(nome):
    """(x, y, w, h) em pixels fisicos de um monitor (nao o Bounds do Tk, que vem escalado por DPI)."""
    dm = novo_devmode()
    if user32.EnumDisplaySettingsW(nome, -1, ctypes.byref(dm)) and dm.dmPelsWidth > 0:
        return dm.dmPositionX, dm.dmPositionY, dm.dmPelsWidth, dm.dmPelsHeight
    return None


# ============================================================ utilidades gerais
def ler(caminho):
    try:
        return caminho.read_text(encoding='utf-8').strip()
    except OSError:
        return ''


def rodar_oculto(args, **kw):
    """subprocess.run escondendo a janela (equivalente ao -WindowStyle Hidden do PowerShell)."""
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    return subprocess.run(args, startupinfo=si, creationflags=CREATE_NO_WINDOW,
                           capture_output=True, text=True, **kw)


def elevar(exe, args, esperar=True):
    """Roda um programa como administrador (equivalente ao Start-Process -Verb RunAs do PowerShell).
    O Windows mostra o proprio aviso de UAC; quem aprova e o usuario. Devolve o codigo de saida ou None
    se o usuario recusou o UAC."""
    params = subprocess.list2cmdline(args)
    SEE_MASK_NOCLOSEPROCESS = 0x00000040
    SW_HIDE = 0

    class SHELLEXECUTEINFO(ctypes.Structure):
        _fields_ = [
            ('cbSize', wt.DWORD), ('fMask', ctypes.c_ulong), ('hwnd', wt.HWND),
            ('lpVerb', wt.LPCWSTR), ('lpFile', wt.LPCWSTR), ('lpParameters', wt.LPCWSTR),
            ('lpDirectory', wt.LPCWSTR), ('nShow', ctypes.c_int), ('hInstApp', wt.HINSTANCE),
            ('lpIDList', ctypes.c_void_p), ('lpClass', wt.LPCWSTR), ('hkeyClass', wt.HKEY),
            ('dwHotKey', wt.DWORD), ('hIconOrMonitor', wt.HANDLE), ('hProcess', wt.HANDLE),
        ]

    sei = SHELLEXECUTEINFO()
    sei.cbSize = ctypes.sizeof(sei)
    sei.fMask = SEE_MASK_NOCLOSEPROCESS
    sei.lpVerb = 'runas'
    sei.lpFile = str(exe)
    sei.lpParameters = params
    sei.nShow = SW_HIDE
    if not ctypes.windll.shell32.ShellExecuteExW(ctypes.byref(sei)):
        return None  # UAC recusado/cancelado
    if esperar and sei.hProcess:
        WAIT_TIMEOUT_MS = 60000
        ctypes.windll.kernel32.WaitForSingleObject(sei.hProcess, WAIT_TIMEOUT_MS)
        code = wt.DWORD()
        ctypes.windll.kernel32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(sei.hProcess)
        return code.value
    return 0


# ============================================================ driver do monitor virtual
_drv_cache = {'valor': None, 't': 0}


def driver_instalado(forcar=False):
    """O driver esta instalado se o Windows tem o pacote mttvdd.inf (pnputil). O vdd_settings.xml NAO
    conta: ele continua no disco depois de desinstalar o driver."""
    if not forcar and _drv_cache['valor'] is not None and (time.time() - _drv_cache['t']) < 20:
        return _drv_cache['valor']
    try:
        r = rodar_oculto(['pnputil', '/enum-drivers'])
        achou = 'mttvdd.inf' in r.stdout.lower()
    except OSError:
        achou = False
    _drv_cache['valor'] = achou
    _drv_cache['t'] = time.time()
    return achou


def baixar_driver(zip_local=None, log=print):
    """Baixa (ou usa zip_local), confere o SHA-256 e extrai. Devolve (inf_path, devcon_path) ou (None, None)."""
    DRV_PASTA.mkdir(parents=True, exist_ok=True)
    zip_path = Path(zip_local) if zip_local else DRV_PASTA / 'VDD.Control.25.7.23.zip'
    if not zip_local and not zip_path.exists():
        log('Baixando o driver do GitHub (68 MB)...')
        urllib.request.urlretrieve(DRV_URL, zip_path)
    sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if sha != DRV_SHA256:
        if not zip_local:
            zip_path.unlink(missing_ok=True)
        log(f'ERRO: o arquivo nao confere com o hash esperado ({sha}). Nao foi usado.')
        return None, None
    log('Arquivo verificado (SHA-256 confere).')
    dest = DRV_PASTA / 'VDD'
    arco = 'ARM64' if os.environ.get('PROCESSOR_ARCHITECTURE') == 'ARM64' else 'x86'
    inf = dest / 'SignedDrivers' / arco / 'VDD' / 'MttVDD.inf'
    devcon = dest / 'Dependencies' / 'devcon.exe'
    # sempre extrai do zip verificado (arquivos antigos/alterados na pasta nunca sao reaproveitados)
    if dest.exists():
        shutil.rmtree(dest)
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(dest)
    if not inf.exists() or not devcon.exists():
        log('ERRO: driver ou devcon.exe nao estao no pacote.')
        return None, None
    return inf, devcon


def instalar_driver(log, confirmar=messagebox.askyesno):
    if driver_instalado(forcar=True):
        log('O driver ja esta instalado.')
        return
    if not confirmar(
        'Instalar driver',
        'Vou baixar o Virtual Display Driver (68 MB) do GitHub oficial do projeto VirtualDrivers, versao 25.7.23, '
        'conferir o SHA-256 e instalar com o devcon.exe da Microsoft (sem abrir mais nenhuma janela).\n\n'
        'O Windows vai pedir permissao de administrador, so para esse comando. Continuar?',
    ):
        log('Instalacao cancelada.')
        return
    log('Baixando e verificando o driver (pode levar alguns minutos)...')
    inf, devcon = baixar_driver(log=log)
    if not inf:
        return
    log('Instalando (confirme o pedido de administrador do Windows)...')
    codigo = elevar(devcon, ['install', str(inf), 'Root\\MttVDD'])
    if codigo is None:
        log('Pedido de administrador negado ou cancelado.')
        return
    time.sleep(2)
    log('Driver instalado.' if driver_instalado(forcar=True) else f'Nao confirmei a instalacao (devcon codigo {codigo}); reinicie o notebook e confira de novo.')


def desinstalar_driver(log, confirmar=messagebox.askyesno):
    if not driver_instalado(forcar=True):
        log('O driver nao esta instalado.')
        return
    if not confirmar(
        'Desinstalar driver',
        'Desinstalar o Virtual Display Driver? As telas virtuais deixam de existir e o envio para o Pi e parado.\n\n'
        'O Windows vai pedir permissao de administrador.',
    ):
        log('Desinstalacao cancelada.')
        return
    log('Parando o envio...')
    parar_tudo(log)
    devcon = DRV_PASTA / 'VDD' / 'Dependencies' / 'devcon.exe'
    if devcon.exists():
        log('Removendo o driver com devcon.exe (confirme o pedido de administrador)...')
        codigo = elevar(devcon, ['remove', 'Root\\MttVDD'])
    else:
        # devcon nao esta em cache (ex.: instalado numa versao antiga do programa): pnputil como reserva
        log('Removendo o driver com pnputil (confirme o pedido de administrador)...')
        r = rodar_oculto(['pnputil', '/enum-drivers'])
        oem = None
        for bloco in r.stdout.split('\n\n'):
            if 'mttvdd.inf' in bloco.lower():
                for linha in bloco.splitlines():
                    if 'oem' in linha.lower() and '.inf' in linha.lower():
                        oem = linha.split(':')[-1].strip()
                        break
                break
        if not oem:
            log('Nao encontrei o pacote do driver no Windows.')
            return
        codigo = elevar(Path(os.environ['WINDIR']) / 'System32' / 'pnputil.exe',
                         ['/delete-driver', oem, '/uninstall', '/force'])
    if codigo is None:
        log('Pedido de administrador negado ou cancelado.')
        return
    time.sleep(2)
    log('O driver ainda aparece instalado; reinicie o notebook e confira de novo.' if driver_instalado(forcar=True) else 'Driver desinstalado.')


# ============================================================ tela estendida (ffmpeg)
def _pingar(ip):
    r = rodar_oculto(['ping', '-n', '1', '-w', '1000', ip])
    return r.returncode == 0


def _testa_encoder(nome):
    args = {'qsv': ['-c:v', 'h264_qsv'], 'nvenc': ['-c:v', 'h264_nvenc'], 'x264': ['-c:v', 'libx264']}[nome]
    r = rodar_oculto(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                       '-i', 'testsrc2=size=640x360:rate=10', '-frames:v', '5'] + args + ['-f', 'null', '-'])
    return r.returncode == 0


def _args_encoder(nome, fps, bitrate):
    if nome == 'qsv':
        return ['-c:v', 'h264_qsv', '-preset', 'veryfast', '-b:v', bitrate, '-maxrate', bitrate,
                '-g', str(fps), '-look_ahead', '0', '-bf', '0']
    if nome == 'nvenc':
        return ['-c:v', 'h264_nvenc', '-preset', 'p1', '-tune', 'll', '-b:v', bitrate, '-maxrate', bitrate,
                '-g', str(fps), '-bf', '0']
    return ['-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-b:v', bitrate,
            '-maxrate', bitrate, '-bufsize', '2M', '-g', str(fps), '-pix_fmt', 'yuv420p']


def parar_tudo(log=print):
    if not PID_FILE.exists():
        log('Nada em execucao.')
        return
    for linha in PID_FILE.read_text().splitlines():
        linha = linha.strip()
        if linha.isdigit():
            rodar_oculto(['taskkill', '/PID', linha, '/F'])
    PID_FILE.unlink(missing_ok=True)
    log('Transmissao parada.')


def transmitindo():
    if not PID_FILE.exists():
        return 0
    n = 0
    for linha in PID_FILE.read_text().splitlines():
        linha = linha.strip()
        if linha.isdigit() and _processo_vivo(int(linha)):
            n += 1
    return n


def _processo_vivo(pid):
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    h = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return False
    ctypes.windll.kernel32.CloseHandle(h)
    return True


def ligar_stream(n, ip, log):
    telas = [t for t in modo_real_virtuais() if t]
    if len(telas) < n:
        log(f'So ha {len(telas)} tela(s) virtual(is) ativa(s); preciso de {n}. Ligue as telas virtuais primeiro.')
        return False
    portas = [5004, 5006]
    if len(portas) < n:
        log('Portas insuficientes para o numero de telas.')
        return False
    encoder = 'x264'
    for e in ('nvenc', 'qsv'):
        if _testa_encoder(e):
            encoder = e
            break
    log(f'Codificador: {encoder}')
    enc = _args_encoder(encoder, 30, '3M')
    parar_tudo(lambda *_: None)
    ids = []
    for i in range(n):
        x, y, w, h = telas[i]
        destino = f'udp://{ip}:{portas[i]}?pkt_size=1316'
        args = ['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-f', 'gdigrab', '-framerate', '30',
                '-offset_x', str(x), '-offset_y', str(y), '-video_size', f'{w}x{h}',
                '-draw_mouse', '1', '-i', 'desktop'] + enc + ['-f', 'mpegts', destino]
        logf = open(PASTA / f'estender-tela{i + 1}.log', 'wb')
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        p = subprocess.Popen(args, startupinfo=si, creationflags=CREATE_NO_WINDOW, stderr=logf, stdout=subprocess.DEVNULL)
        ids.append(p.pid)
        log(f'Tela {i + 1}: monitor virtual ({w}x{h} em {x},{y}) -> {destino}  (PID {p.pid})')
    PID_FILE.write_text('\n'.join(str(i) for i in ids))
    log('Transmitindo.')
    return True


def modo_real_virtuais():
    """[(x,y,w,h)] das telas virtuais anexadas, da esquerda para a direita, em pixels reais."""
    vs = []
    for nome, anexado in get_telas_virtuais():
        if not anexado:
            continue
        m = modo_real(nome)
        if m:
            vs.append(m)
    vs.sort(key=lambda t: t[0])
    return vs


# ============================================================ acoes de alto nivel (janela)
def validar_ip(txt):
    import re
    return bool(re.fullmatch(r'\d{1,3}(\.\d{1,3}){3}([,; ]+\d{1,3}(\.\d{1,3}){3})*', txt))


def escolher_pi_que_responde(ip_texto):
    candidatos = [c for c in __import__('re').split(r'[,; ]+', ip_texto) if c]
    for c in candidatos:
        if _pingar(c):
            return c
    return candidatos[0]


def ligar(n, ip_texto, log):
    if not driver_instalado():
        log('Driver do monitor virtual nao instalado. Use o botao Instalar driver.')
        return False
    if not validar_ip(ip_texto):
        log('IP invalido. Use, por exemplo, 192.168.0.43 (cabo e Wi-Fi separados por virgula).')
        return False
    IP_FILE.write_text(ip_texto)
    ip = escolher_pi_que_responde(ip_texto)
    if not _pingar(ip):
        log(f'Aviso: o Pi ({ip}) nao respondeu ao ping. Confira o IP e se o PC esta na mesma rede (cabo ou Wi-Fi).')
    log(f'Preparando {n} tela(s) virtual(is)...')
    if len(get_telas_virtuais()) < n:
        # cada instancia do driver cria N monitores: com 2 instancias instaladas, contagem 1 ja da 2 telas
        instancias = max(1, len(rodar_oculto(['pnputil', '/enum-devices', '/class', 'Display']).stdout.split('Instance ID:')) - 1)
        por_inst = -(-n // instancias)  # ceil
        if not _definir_contagem(por_inst):
            log('Nao consegui pedir os monitores ao driver.')
            return False
        for _ in range(25):
            if len(get_telas_virtuais()) >= n:
                break
            time.sleep(0.8)
    if len(get_telas_virtuais()) < n:
        log('O driver nao criou os monitores. Reinicie o notebook e tente de novo.')
        return False
    ativas = anexar_telas_virtuais(n, log=log)
    if ativas < n:
        log('As telas virtuais nao entraram na area de trabalho. Tente Win+P > Estender.')
        return False
    log(f'{ativas} tela(s) virtual(is) ativa(s).')
    log(f'Enviando ao Pi ({ip})...')
    ok = ligar_stream(n, ip, log)
    t = transmitindo()
    log(f'Pronto: {t} tela(s) sendo enviada(s) ao Pi.' if t >= 1 else 'O envio nao iniciou (veja estender-tela1.log).')
    return t >= 1


def _definir_contagem(n):
    if not CFG_VDD.exists():
        return False
    try:
        import re
        xml = CFG_VDD.read_text(encoding='utf-8')
        xml = re.sub(r'<count>\d+</count>', f'<count>{n}</count>', xml, count=1)
        CFG_VDD.write_text(xml, encoding='utf-8')
        import win32pipe
        import win32file
        h = win32file.CreateFile(r'\\.\pipe\MTTVirtualDisplayPipe', win32file.GENERIC_WRITE, 0, None,
                                  win32file.OPEN_EXISTING, 0, None)
        win32file.WriteFile(h, 'RELOAD_DRIVER'.encode())
        time.sleep(0.8)
        win32file.CloseHandle(h)
        return True
    except Exception:
        return False


def desligar(log, remover=False):
    log('Parando o envio...')
    parar_tudo(log)
    if remover:
        log('Removendo os monitores virtuais do driver (para voltar, reinicie o notebook)...')
        if not _definir_contagem(0):
            log('Nao consegui recarregar o driver; reinicie o notebook para remover as telas.')
        time.sleep(3)
    else:
        log('Desativando as telas virtuais...')
        desanexar_telas_virtuais()
    log(f'Pronto. Telas extras ativas: {telas_extras()}')


def telas_extras():
    return sum(1 for _, a in get_telas_virtuais() if a)


# ============================================================ configurações do Pi (pela rede)
CONFIG_PORTA = 8765
CAMPOS_CONFIG_PI = ('DISPLAY1_NAME', 'DISPLAY_MODE', 'LAZYCAST_AUTH', 'LAZYCAST_PIN', 'SCREEN1_SOURCE', 'SCREEN2_SOURCE')


def _meu_ip():
    """IP deste PC na rede local (sem abrir conexão de verdade: UDP 'connect' só resolve a rota)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


def descobrir_pis(timeout=0.3, max_workers=48):
    """Varre a rede local (mesmo /24 deste PC) procurando o servidor de configuração do LazyCast
    (porta 8765): só acha Raspberry Pis com o LazyCast rodando, não qualquer dispositivo na rede.
    Devolve [{'ip':..., 'nome':...}], mais rápido primeiro (ordem de resposta)."""
    meu_ip = _meu_ip()
    partes = meu_ip.split('.')
    if len(partes) != 4:
        return []
    prefixo = '.'.join(partes[:3])
    alvo = {f'{prefixo}.{i}' for i in range(1, 255)} - {meu_ip}

    def checar(ip):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        try:
            if s.connect_ex((ip, CONFIG_PORTA)) != 0:
                return None
        finally:
            s.close()
        try:
            cfg = buscar_config_pi(ip)
            return {'ip': ip, 'nome': cfg.get('DISPLAY1_NAME') or ip}
        except (OSError, ValueError):
            return {'ip': ip, 'nome': ip}

    achados = []
    with concurrent.futures.ThreadPoolExecutor(max_workers) as ex:
        for r in ex.map(checar, alvo):
            if r:
                achados.append(r)
    achados.sort(key=lambda p: p['ip'])
    return achados


def buscar_config_pi(ip):
    """GET no servidor de configuração do Pi (config_server.py, mesma rede local, sem senha). Levanta
    excecao se o Pi nao responder (a chamada trata isso)."""
    with urllib.request.urlopen(f'http://{ip}:{CONFIG_PORTA}/api/config', timeout=4) as r:
        return json.loads(r.read().decode('utf-8'))


def gravar_config_pi(ip, campos):
    """POST com as mudancas; o Pi grava e reinicia o servico sozinho (igual ao 'Salvar e aplicar' do
    painel dele). Devolve (ok, mensagem_de_erro_ou_vazio)."""
    corpo = json.dumps(campos).encode('utf-8')
    req = urllib.request.Request(f'http://{ip}:{CONFIG_PORTA}/api/config', data=corpo, method='POST',
                                  headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            resp = json.loads(r.read().decode('utf-8'))
        return bool(resp.get('ok')), resp.get('mensagem', '')
    except urllib.error.HTTPError as e:
        try:
            resp = json.loads(e.read().decode('utf-8'))
            return False, resp.get('erro', str(e))
        except (ValueError, OSError):
            return False, str(e)


def miracast(nome, log):
    if nome:
        NOME_FILE.write_text(nome)
    log(f"Abrindo o painel de transmitir: escolha '{nome}' na lista." if nome else
        'Abrindo o painel de transmitir: escolha o receptor LazyCast na lista.')
    os.startfile('ms-settings-connectabledevices:devicediscovery')


# ============================================================ janela (Tkinter) + bandeja (pystray)
class App:
    def __init__(self, root):
        self.root = root
        self.ocupado = False
        self.finalizado = False
        self.tray_icon = None
        root.title('LazyCast para Windows')
        root.resizable(False, False)
        root.protocol('WM_DELETE_WINDOW', self.on_fechar)
        root.bind('<Unmap>', self.on_minimizar)
        try:
            root.iconbitmap(str(Path(__file__).parent / 'lazycast.ico'))
        except (tk.TclError, OSError):
            pass
        try:
            ttk.Style().configure('Accent.TButton', font=('Segoe UI', 9, 'bold'))
        except tk.TclError:
            pass

        pad = {'padx': 10, 'pady': 6}

        # ---- 1. Driver
        f1 = ttk.LabelFrame(root, text='1. Driver do monitor virtual')
        f1.grid(row=0, column=0, sticky='ew', **pad)
        self.lbl_driver = ttk.Label(f1, font=('Segoe UI', 11, 'bold'))
        self.lbl_driver.grid(row=0, column=0, sticky='w', padx=10, pady=(8, 0))
        self.lbl_driver_info = ttk.Label(f1, foreground='#666666')
        self.lbl_driver_info.grid(row=1, column=0, sticky='w', padx=10, pady=(0, 8))
        self.btn_driver = ttk.Button(f1, text='Instalar driver', command=self.on_instalar_driver)
        self.btn_driver.grid(row=0, column=1, rowspan=2, padx=10)
        self.btn_desinst = ttk.Button(f1, text='Desinstalar driver', command=self.on_desinstalar_driver)

        # ---- 2. Raspberry Pi: descoberto na rede, escolhe e clica Conectar
        self.pi_conectado = None      # {'ip':..., 'nome':...} só depois de Conectar dar certo
        self._pis_lista = []
        f2 = ttk.LabelFrame(root, text='2. Raspberry Pi')
        f2.grid(row=1, column=0, sticky='ew', **pad)
        ttk.Label(f2, text='Encontrados na rede (mesmo Wi-Fi/cabo deste PC):').grid(row=0, column=0, columnspan=3, sticky='w', padx=10, pady=(8, 0))
        self.cmb_pis = ttk.Combobox(f2, width=42, state='readonly')
        self.cmb_pis.grid(row=1, column=0, columnspan=3, sticky='w', padx=10, pady=(2, 6))
        self.cmb_pis.bind('<<ComboboxSelected>>', self.on_selecionar_pi)
        self.btn_pi_atualizar = ttk.Button(f2, text='Atualizar lista', command=self.on_atualizar_lista)
        self.btn_pi_atualizar.grid(row=2, column=0, sticky='w', padx=10, pady=(0, 8))
        self.btn_pi_conectar = ttk.Button(f2, text='Conectar', command=self.on_conectar_pi, state='disabled', style='Accent.TButton')
        self.btn_pi_conectar.grid(row=2, column=1, sticky='w', padx=10, pady=(0, 8))
        self.lbl_pi_busca = ttk.Label(f2, text='', foreground='#666666')
        self.lbl_pi_busca.grid(row=2, column=2, sticky='w', padx=10, pady=(0, 8))
        self.lbl_pi_conectado = ttk.Label(f2, text='○ Não conectado', foreground='#be2828')
        self.lbl_pi_conectado.grid(row=3, column=0, columnspan=3, sticky='w', padx=10, pady=(0, 8))

        # ---- 3. Tela estendida (só funciona conectado a um Pi). "Telas" é um único número: o mesmo
        # controla quantas telas virtuais o Windows cria/envia E quantas o Pi espera receber (Salvar no
        # Pi grava aqui também) — ter dois números editáveis separados (um no Windows, outro no Pi) e
        # deixá-los dessincronizar é a causa mais comum de "Tela 2 não aparece".
        f3 = ttk.LabelFrame(root, text='3. Tela estendida (cabo ou Wi-Fi)')
        f3.grid(row=2, column=0, sticky='ew', **pad)
        ttk.Label(f3, text='Quantas telas (Windows e Pi)').grid(row=0, column=0, sticky='w', padx=10, pady=(8, 0))
        self.cmb_n = ttk.Combobox(f3, values=['1', '2'], width=5, state='disabled')
        self.cmb_n.set('2')
        self.cmb_n.grid(row=1, column=0, sticky='w', padx=10)
        self.btn_ligar = ttk.Button(f3, text='Ligar tela virtual', command=self.on_ligar, state='disabled', style='Accent.TButton')
        self.btn_ligar.grid(row=2, column=0, sticky='w', padx=10, pady=10)
        self.btn_desligar = ttk.Button(f3, text='Desligar', command=self.on_desligar, state='disabled')
        self.btn_desligar.grid(row=2, column=1, sticky='w', padx=10, pady=10)
        self.var_remover = tk.BooleanVar()
        self.chk_remover = ttk.Checkbutton(f3, text='Ao desligar, remover tambem os monitores do driver (so voltam apos reiniciar)',
                                            variable=self.var_remover, state='disabled')
        self.chk_remover.grid(row=3, column=0, columnspan=2, sticky='w', padx=10, pady=(0, 8))

        # ---- 4. Miracast — sem campo de nome (usa o Pi conectado na seção 2; nada pra digitar de novo)
        f4 = ttk.LabelFrame(root, text='4. Miracast (Transmitir do Windows)')
        f4.grid(row=3, column=0, sticky='ew', **pad)
        self.lbl_miracast = ttk.Label(f4, text='Conecte a um Pi na seção 2 primeiro.', foreground='#666666')
        self.lbl_miracast.grid(row=0, column=0, sticky='w', padx=10, pady=8)
        ttk.Button(f4, text='Conectar', command=self.on_miracast).grid(row=0, column=1, padx=10)

        # ---- 5. Configurações do Pi (só editável depois de Conectar na seção 2)
        f5 = ttk.LabelFrame(root, text='5. Configurações do Pi (nome, PIN, fonte de cada tela)')
        f5.grid(row=4, column=0, sticky='ew', **pad)
        ttk.Label(f5, text='Nome da rede').grid(row=0, column=0, sticky='w', padx=10, pady=(8, 0))
        self.txt_pi_nome = ttk.Entry(f5, width=22, state='disabled')
        self.txt_pi_nome.grid(row=1, column=0, sticky='w', padx=10)
        ttk.Label(f5, text='Tela 1 vem de').grid(row=2, column=0, sticky='w', padx=10, pady=(8, 0))
        self.lbl_pi_fonte2 = ttk.Label(f5, text='Tela 2 vem de')
        self.lbl_pi_fonte2.grid(row=2, column=1, sticky='w', padx=10, pady=(8, 0))
        fontes = ['auto (sem fio/Miracast)', 'stream:5004 (Windows, rede)', 'stream:5006 (Windows, rede)']
        self.cmb_pi_fonte1 = ttk.Combobox(f5, values=fontes, width=24, state='disabled')
        self.cmb_pi_fonte1.grid(row=3, column=0, sticky='w', padx=10)
        self.cmb_pi_fonte2 = ttk.Combobox(f5, values=fontes, width=24, state='disabled')
        self.cmb_pi_fonte2.grid(row=3, column=1, sticky='w', padx=10)
        ttk.Label(f5, text='Conexão').grid(row=4, column=0, sticky='w', padx=10, pady=(8, 0))
        self.cmb_pi_auth = ttk.Combobox(f5, values=['Sem PIN (mais fácil)', 'Com PIN'], width=18, state='disabled')
        self.cmb_pi_auth.grid(row=5, column=0, sticky='w', padx=10)
        self.txt_pi_pin = ttk.Entry(f5, width=12, state='disabled')
        self.txt_pi_pin.grid(row=5, column=1, sticky='w', padx=10)
        self.btn_pi_recarregar = ttk.Button(f5, text='Recarregar do Pi', command=self.on_recarregar_config_pi, state='disabled')
        self.btn_pi_recarregar.grid(row=6, column=0, sticky='w', padx=10, pady=10)
        self.btn_pi_salvar = ttk.Button(f5, text='Salvar no Pi', command=self.on_salvar_config_pi, state='disabled')
        self.btn_pi_salvar.grid(row=6, column=1, sticky='w', padx=10, pady=10)

        self.cmb_n.bind('<<ComboboxSelected>>', lambda e: self._atualizar_dependencias())
        self.cmb_pi_auth.bind('<<ComboboxSelected>>', lambda e: self._atualizar_dependencias())

        # ---- 6. Atividade (estado atual + log), com rolagem
        f6 = ttk.LabelFrame(root, text='6. Atividade')
        f6.grid(row=5, column=0, sticky='ew', **pad)
        self.lbl_estado = ttk.Label(f6, foreground='#666666')
        self.lbl_estado.grid(row=0, column=0, sticky='w', padx=10, pady=(8, 4))
        log_frame = ttk.Frame(f6)
        log_frame.grid(row=1, column=0, sticky='ew', padx=10, pady=(0, 10))
        self.txt_log = tk.Text(log_frame, width=62, height=8, state='disabled', font=('Consolas', 9), wrap='word')
        self.txt_log.grid(row=0, column=0, sticky='ew')
        scroll_log = ttk.Scrollbar(log_frame, orient='vertical', command=self.txt_log.yview)
        scroll_log.grid(row=0, column=1, sticky='ns')
        self.txt_log.configure(yscrollcommand=scroll_log.set)

        self.log('Pronto.')
        self.atualizar()
        self._timer()
        self.on_atualizar_lista()  # procura Pis na rede ao abrir; não conecta sozinho (só ao clicar Conectar)

    # ---- log/estado
    def log(self, msg):
        def _add():
            self.txt_log.configure(state='normal')
            self.txt_log.insert('end', str(msg) + '\n')
            self.txt_log.see('end')
            self.txt_log.configure(state='disabled')
        self.root.after(0, _add)

    def ocupar(self, sim):
        self.ocupado = sim
        estado = 'disabled' if sim else 'normal'
        for b in (self.btn_ligar, self.btn_desligar, self.btn_driver, self.btn_desinst,
                  self.btn_pi_atualizar, self.btn_pi_conectar, self.btn_pi_recarregar, self.btn_pi_salvar):
            try:
                b.configure(state=estado)
            except tk.TclError:
                pass
        if not sim:
            self.atualizar()
            # os botões/campos da seção do Pi voltam a refletir se está conectado (não ficam sempre 'normal')
            (self._desbloquear_widgets() if self.pi_conectado else self._bloquear_widgets())

    def atualizar(self):
        t = transmitindo()
        e = telas_extras()
        di = driver_instalado()
        if di:
            self.lbl_driver.configure(text='● Driver ja instalado', foreground='#1e8236')
            self.lbl_driver_info.configure(text='Virtual Display Driver (VirtualDrivers)')
            self.btn_driver.grid_remove()
            self.btn_desinst.grid(row=0, column=1, rowspan=2, padx=10)
        else:
            self.lbl_driver.configure(text='● Driver nao instalado', foreground='#be2828')
            self.lbl_driver_info.configure(text='Necessario para criar as telas virtuais.')
            self.btn_desinst.grid_remove()
            self.btn_driver.grid(row=0, column=1, rowspan=2, padx=10)
        self.btn_ligar.configure(state=('disabled' if (self.ocupado or not di or not self.pi_conectado) else 'normal'))
        if not self.ocupado:
            pode_desligar = t > 0 or e > 0
            self.btn_desligar.configure(state=('normal' if pode_desligar else 'disabled'))
            self.chk_remover.configure(state=('normal' if pode_desligar else 'disabled'))  # só faz sentido junto do Desligar
        ativo = t > 0 or e > 0
        self.lbl_estado.configure(text=f'{"●" if ativo else "○"} Enviando: {t} fluxo(s)   |   Telas virtuais ativas: {e}',
                                   foreground=('#1e8236' if ativo else '#666666'))

    def _timer(self):
        if not self.ocupado:
            self.atualizar()
        self.root.after(3000, self._timer)

    def _rodar_bg(self, fn):
        def alvo():
            self.ocupar(True)
            try:
                fn()
            except Exception as e:  # nunca deixa uma acao travar o app inteiro
                self.log(f'Erro: {e}')
            finally:
                self.root.after(0, lambda: self.ocupar(False))
        threading.Thread(target=alvo, daemon=True).start()

    # ---- acoes dos botoes
    def on_ligar(self):
        if not self.pi_conectado:
            self.log('Conecte a um Raspberry Pi na seção 2 primeiro.')
            return
        n = int(self.cmb_n.get())
        ip = self.pi_conectado['ip']
        self._rodar_bg(lambda: ligar(n, ip, self.log))

    def on_desligar(self):
        self._rodar_bg(lambda: desligar(self.log, self.var_remover.get()))

    def on_instalar_driver(self):
        self._rodar_bg(lambda: instalar_driver(self.log, self._confirmar))

    def on_desinstalar_driver(self):
        self._rodar_bg(lambda: desinstalar_driver(self.log, self._confirmar))

    def _confirmar(self, titulo, msg):
        resultado = {}

        def perguntar():
            resultado['v'] = messagebox.askyesno(titulo, msg, parent=self.root)
        self.root.after(0, perguntar)
        while 'v' not in resultado:
            time.sleep(0.05)
        return resultado['v']

    def on_miracast(self):
        miracast(self.pi_conectado['nome'] if self.pi_conectado else '', self.log)

    # ---- seção 2 (lista de Pis) e seção 5 (configurações): só editável depois de "Conectar"
    _FONTES_TXT = ['auto (sem fio/Miracast)', 'stream:5004 (Windows, rede)', 'stream:5006 (Windows, rede)']
    _FONTES_RAW = ['auto', 'stream:5004', 'stream:5006']
    _AUTH_TXT = ['Sem PIN (mais fácil)', 'Com PIN']
    _AUTH_RAW = ['pbc', 'pin']

    def _bg_leve(self, fn):
        """Como _rodar_bg, mas sem mexer em Ligar/Desligar/driver (só a varredura da rede usa isso;
        não deve travar os controles de uma sessão já conectada)."""
        threading.Thread(target=fn, daemon=True).start()

    def on_atualizar_lista(self):
        self.btn_pi_atualizar.configure(state='disabled')
        self.lbl_pi_busca.configure(text='Procurando...', foreground='#666666')
        self.log('Procurando Raspberry Pi na rede...')

        def fazer():
            achados = descobrir_pis()
            self.root.after(0, lambda: self._preencher_lista(achados))
        self._bg_leve(fazer)

    def _preencher_lista(self, achados):
        self._pis_lista = achados
        self.cmb_pis.configure(values=[f"{p['nome']}  ({p['ip']})" for p in achados])
        self.btn_pi_atualizar.configure(state='normal')
        self.lbl_pi_busca.configure(text=(f'{len(achados)} encontrado(s)' if achados else 'Nenhum encontrado'),
                                     foreground=('#1e8236' if achados else '#be2828'))
        self.log(f'{len(achados)} Raspberry Pi encontrado(s) na rede.' if achados else
                  'Nenhum Raspberry Pi com o LazyCast encontrado na rede (tente Atualizar lista de novo).')
        # se o Pi da última vez está na lista, só realça (não conecta sozinho: precisa clicar Conectar)
        ultimo = ler(IP_FILE)
        for i, p in enumerate(achados):
            if p['ip'] == ultimo:
                self.cmb_pis.current(i)
                self.on_selecionar_pi(None)
                break

    def on_selecionar_pi(self, event):
        i = self.cmb_pis.current()
        if i < 0:
            self.btn_pi_conectar.configure(state='disabled')
            return
        escolhido = self._pis_lista[i]
        self.btn_pi_conectar.configure(state='normal')
        if not self.pi_conectado or self.pi_conectado['ip'] != escolhido['ip']:
            self._bloquear_widgets()  # trocou de Pi na lista: precisa clicar Conectar de novo

    def on_conectar_pi(self):
        i = self.cmb_pis.current()
        if i < 0:
            return
        alvo = self._pis_lista[i]

        def ao_sucesso(cfg):
            nome = cfg.get('DISPLAY1_NAME') or alvo['nome']
            self.pi_conectado = {'ip': alvo['ip'], 'nome': nome}
            IP_FILE.write_text(alvo['ip'])
            self._desbloquear_widgets(cfg)
            self.log(f"Conectado a {nome} ({alvo['ip']}).")
        self._buscar_config(alvo['ip'], ao_sucesso, verbo='conectar a')

    def _buscar_config(self, ip, ao_sucesso, verbo='conectar a'):
        """Busca a config do Pi em segundo plano; chama ao_sucesso(cfg) na thread da UI se der certo.
        Usada tanto por Conectar quanto por Recarregar — evita repetir o mesmo try/except duas vezes."""
        def fazer():
            try:
                cfg = buscar_config_pi(ip)
            except (OSError, ValueError) as e:
                self.log(f'Não consegui {verbo} ({ip}): {e}')
                return
            self.root.after(0, lambda: ao_sucesso(cfg))
        self._rodar_bg(fazer)

    def on_recarregar_config_pi(self):
        if not self.pi_conectado:
            return

        def ao_sucesso(cfg):
            self._preencher_config_pi(cfg)
            self.log('Configurações do Pi atualizadas aqui.')
        self._buscar_config(self.pi_conectado['ip'], ao_sucesso, verbo='buscar as configurações do Pi')

    def _preencher_config_pi(self, cfg):
        self.txt_pi_nome.delete(0, 'end')
        self.txt_pi_nome.insert(0, cfg.get('DISPLAY1_NAME', ''))
        self.cmb_n.set(cfg.get('DISPLAY_MODE', '2'))  # "quantas telas" é um único número (seção 3), não duplicado aqui
        for combo, chave in ((self.cmb_pi_fonte1, 'SCREEN1_SOURCE'), (self.cmb_pi_fonte2, 'SCREEN2_SOURCE')):
            raw = cfg.get(chave, 'auto')
            idx = self._FONTES_RAW.index(raw) if raw in self._FONTES_RAW else 0
            combo.set(self._FONTES_TXT[idx])
        auth = cfg.get('LAZYCAST_AUTH', 'pbc')
        self.cmb_pi_auth.set(self._AUTH_TXT[self._AUTH_RAW.index(auth)] if auth in self._AUTH_RAW else self._AUTH_TXT[0])
        self.txt_pi_pin.delete(0, 'end')
        self.txt_pi_pin.insert(0, cfg.get('LAZYCAST_PIN', ''))
        self._atualizar_dependencias()

    def _atualizar_dependencias(self):
        """Esconde/desativa campos que não fazem sentido com a escolha atual: Tela 2 só importa com
        2 telas, e o PIN só importa com 'Com PIN' — evita deixar campo morto editável na tela."""
        duas_telas = self.cmb_n.get() == '2'
        estado_base = 'readonly' if self.pi_conectado else 'disabled'
        self.lbl_pi_fonte2.configure(state=(estado_base if duas_telas else 'disabled'))
        self.cmb_pi_fonte2.configure(state=(estado_base if duas_telas else 'disabled'))

        com_pin = self.cmb_pi_auth.get() == 'Com PIN'
        self.txt_pi_pin.configure(state=(('normal' if self.pi_conectado else 'disabled') if com_pin else 'disabled'))

    def _bloquear_widgets(self):
        self.pi_conectado = None
        for w in (self.btn_pi_recarregar, self.btn_pi_salvar):
            w.configure(state='disabled')
        for w in (self.txt_pi_nome, self.cmb_pi_fonte1, self.cmb_pi_fonte2, self.cmb_pi_auth, self.txt_pi_pin, self.cmb_n):
            w.configure(state='disabled')
        self.lbl_pi_conectado.configure(text='○ Não conectado', foreground='#be2828')
        self.lbl_miracast.configure(text='Conecte a um Pi na seção 2 primeiro.')
        self._atualizar_dependencias()
        self.atualizar()  # Ligar também depende de pi_conectado

    def _desbloquear_widgets(self, cfg=None):
        for w in (self.btn_pi_recarregar, self.btn_pi_salvar):
            w.configure(state='normal')
        for w in (self.txt_pi_nome, self.txt_pi_pin):
            w.configure(state='normal')
        for w in (self.cmb_pi_fonte1, self.cmb_pi_fonte2, self.cmb_pi_auth, self.cmb_n):
            w.configure(state='readonly')
        if cfg:
            self._preencher_config_pi(cfg)
        if self.pi_conectado:
            self.lbl_pi_conectado.configure(text=f"● Conectado a {self.pi_conectado['nome']} ({self.pi_conectado['ip']})",
                                             foreground='#1e8236')
            self.lbl_miracast.configure(text=f"Conectar abre o Transmitir do Windows; escolha \"{self.pi_conectado['nome']}\".")
        self._atualizar_dependencias()
        self.atualizar()

    def on_salvar_config_pi(self):
        if not self.pi_conectado:
            return
        ip = self.pi_conectado['ip']
        campos = {
            'DISPLAY1_NAME': self.txt_pi_nome.get().strip(),
            'DISPLAY_MODE': self.cmb_n.get() or '1',
            'SCREEN1_SOURCE': self._FONTES_RAW[self._FONTES_TXT.index(self.cmb_pi_fonte1.get())] if self.cmb_pi_fonte1.get() in self._FONTES_TXT else 'auto',
            'SCREEN2_SOURCE': self._FONTES_RAW[self._FONTES_TXT.index(self.cmb_pi_fonte2.get())] if self.cmb_pi_fonte2.get() in self._FONTES_TXT else 'auto',
            'LAZYCAST_AUTH': self._AUTH_RAW[self._AUTH_TXT.index(self.cmb_pi_auth.get())] if self.cmb_pi_auth.get() in self._AUTH_TXT else 'pbc',
            'LAZYCAST_PIN': self.txt_pi_pin.get().strip(),
        }

        def fazer():
            self.log('Salvando no Pi (ele reinicia o serviço sozinho)...')
            ok, msg = gravar_config_pi(ip, campos)
            if ok:
                self.pi_conectado['nome'] = campos['DISPLAY1_NAME']
            self.log('Configurações salvas no Pi.' if ok else f'Não consegui salvar no Pi: {msg}')
        self._rodar_bg(fazer)

    # ---- bandeja: minimizar deixa rodando; Sair/fechar para tudo de verdade
    def on_minimizar(self, event):
        if event.widget is not self.root or self.root.state() != 'iconic':
            return
        self.root.withdraw()
        self._tray_mostrar()

    def _tray_mostrar(self):
        if self.tray_icon:
            return
        import pystray
        from PIL import Image, ImageDraw
        img = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((4, 4, 60, 60), radius=14, fill=(30, 130, 190, 255))
        d.rectangle((16, 22, 48, 40), fill=(255, 255, 255, 255))
        d.polygon([(28, 44), (36, 44), (32, 52)], fill=(255, 255, 255, 255))
        menu = pystray.Menu(
            pystray.MenuItem('Abrir', self._tray_abrir, default=True),
            pystray.MenuItem('Sair (para o envio e solta as telas)', self._tray_sair),
        )
        self.tray_icon = pystray.Icon('LazyCast', img, 'LazyCast para Windows', menu)
        threading.Thread(target=self.tray_icon.run, daemon=True).start()

    def _tray_abrir(self, icon=None, item=None):
        if self.tray_icon:
            self.tray_icon.stop()
            self.tray_icon = None
        self.root.after(0, self._restaurar)

    def _restaurar(self):
        self.root.deiconify()
        self.root.state('normal')
        self.root.lift()
        self.root.focus_force()

    def _tray_sair(self, icon=None, item=None):
        self.root.after(0, self._finalizar_e_fechar)

    def _finalizar_e_fechar(self):
        self.finalizar()
        self.root.destroy()

    def on_fechar(self):
        self.finalizar()
        self.root.destroy()

    def finalizar(self):
        if self.finalizado:
            return
        self.finalizado = True
        if self.tray_icon:
            self.tray_icon.stop()
            self.tray_icon = None
        try:
            desligar(self.log, False)  # so desanexa (rapido); "Ligar" volta na hora, sem reiniciar o driver
        except Exception:
            pass


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == '__main__':
    main()
