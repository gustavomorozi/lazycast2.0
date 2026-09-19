#!/usr/bin/env python3
"""
Simulador de fonte Miracast (o lado do Windows/Android).

Escuta na porta RTSP de controle (7236) e conduz a negociação M1..M7 com o
receiver (d2.py), depois envia pacotes RTP para a client_port informada e
finaliza com TEARDOWN (M8). O objetivo é exercitar o receiver de ponta a ponta
sem hardware.

Uso: mock_source.py [--bind IP] [--port 7236] [--rtp-packets N] [--hold S]
Sai com código 0 se a negociação completa e o receiver responde ao TEARDOWN.
"""
import argparse
import socket
import sys
import time

M1 = 'OPTIONS * RTSP/1.0\r\nCSeq: 1\r\nRequire: org.wfa.wfd1.0\r\n\r\n'

M3_PARAMS = (
    'wfd_video_formats\r\n'
    'wfd_audio_codecs\r\n'
    'wfd_client_rtp_ports\r\n'
    'wfd_uibc_capability\r\n'
    'wfd_display_edid\r\n'
    'wfd_idr_request_capability\r\n'
    'intel_friendly_name\r\n'
    'intel_sink_manufacturer_name\r\n'
    'intel_sink_model_name\r\n'
    'intel_sink_version\r\n'
    'intel_sink_device_URL\r\n'
    'microsoft_cursor\r\n'
)

M4_PARAMS = (
    'wfd_video_formats: 00 00 02 04 00000080 00000000 00000000 00 0000 0000 00 none none\r\n'
    'wfd_audio_codecs: LPCM 00000002 00\r\n'
    'wfd_presentation_URL: rtsp://{ip}/wfd1.0/streamid=0 none\r\n'
    'wfd_client_rtp_ports: RTP/AVP/UDP;unicast {port} 0 mode=play\r\n'
    'wfd_uibc_capability: input_category_list=GENERIC, HIDC;generic_cap_list=Keyboard, Mouse;hidc_cap_list=Keyboard/USB, Mouse/USB;port=7239\r\n'
    'wfd_uibc_setting: enable\r\n'
)

M5 = 'wfd_trigger_method: SETUP\r\n'
M8 = 'wfd_trigger_method: TEARDOWN\r\n'


def log(direction, data):
    print('[source] ' + direction)
    print(data if isinstance(data, str) else data.decode(errors='replace'))
    sys.stdout.flush()


class Rtsp:
    def __init__(self, conn):
        self.conn = conn
        self.buf = b''

    def send(self, text):
        log('<---', text)
        self.conn.sendall(text.encode())

    def recv_message(self, timeout=15):
        """Lê uma mensagem RTSP completa (headers + body por Content-Length)."""
        self.conn.settimeout(timeout)
        while True:
            head_end = self.buf.find(b'\r\n\r\n')
            if head_end != -1:
                head = self.buf[:head_end].decode()
                clen = 0
                for line in head.split('\r\n'):
                    if line.lower().startswith('content-length:'):
                        clen = int(line.split(':', 1)[1].strip())
                total = head_end + 4 + clen
                if len(self.buf) >= total:
                    msg = self.buf[:total].decode()
                    self.buf = self.buf[total:]
                    log('--->', msg)
                    return msg
            chunk = self.conn.recv(4096)
            if not chunk:
                raise ConnectionError('receiver fechou a conexão')
            self.buf += chunk

    def set_parameter(self, cseq, body):
        self.send('SET_PARAMETER rtsp://localhost/wfd1.0 RTSP/1.0\r\n'
                  'Content-Type: text/parameters\r\n'
                  'Content-Length: ' + str(len(body)) + '\r\n'
                  'CSeq: ' + str(cseq) + '\r\n\r\n' + body)


def expect(msg, *needles):
    for n in needles:
        if n not in msg:
            raise AssertionError('esperado %r em:\n%s' % (n, msg))


def parse_client_port(m3resp):
    for line in m3resp.split('\r\n'):
        if line.startswith('wfd_client_rtp_ports:'):
            return int(line.split('unicast')[1].split()[0])
    raise AssertionError('wfd_client_rtp_ports ausente na resposta M3')


def run(args):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.bind, args.port))
    srv.listen(1)
    srv.settimeout(args.accept_timeout)
    print('[source] aguardando receiver em %s:%d' % (args.bind, args.port))
    sys.stdout.flush()
    conn, peer = srv.accept()
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    print('[source] receiver conectado de %s:%d' % peer)
    rtsp = Rtsp(conn)

    # M1
    rtsp.send(M1)
    expect(rtsp.recv_message(), 'RTSP/1.0 200 OK', 'org.wfa.wfd1.0')

    # M2 (do receiver)
    expect(rtsp.recv_message(), 'OPTIONS *', 'CSeq: 1')
    m2resp = ('RTSP/1.0 200 OK\r\nCSeq: 1\r\n'
              'Public: org.wfa.wfd1.0, GET_PARAMETER, SET_PARAMETER\r\n\r\n')
    m3 = ('GET_PARAMETER rtsp://localhost/wfd1.0 RTSP/1.0\r\n'
          'Content-Type: text/parameters\r\n'
          'Content-Length: ' + str(len(M3_PARAMS)) + '\r\n'
          'CSeq: 2\r\n\r\n' + M3_PARAMS)
    if args.coalesce:
        rtsp.send(m2resp + m3)
    else:
        rtsp.send(m2resp)
        time.sleep(0.05)
        rtsp.send(m3)
    m3resp = rtsp.recv_message()
    expect(m3resp, 'RTSP/1.0 200 OK', 'CSeq: 2', 'wfd_video_formats:',
           'wfd_audio_codecs:', 'wfd_client_rtp_ports:')
    client_port = parse_client_port(m3resp)

    # M4
    rtsp.set_parameter(3, M4_PARAMS.format(ip=args.bind, port=client_port))
    expect(rtsp.recv_message(), 'RTSP/1.0 200 OK', 'CSeq: 3')

    # M5
    rtsp.set_parameter(4, M5)
    expect(rtsp.recv_message(), 'RTSP/1.0 200 OK', 'CSeq: 4')

    # M6 (SETUP do receiver)
    m6 = rtsp.recv_message()
    expect(m6, 'SETUP rtsp://', 'client_port=' + str(client_port))
    session = '1A2B3C4D'
    rtsp.send('RTSP/1.0 200 OK\r\nCSeq: 5\r\n'
              'Session: ' + session + ';timeout=30\r\n'
              'Transport: RTP/AVP/UDP;unicast;client_port=' + str(client_port) +
              ';server_port=19000-19001\r\n\r\n')

    # M7 (PLAY do receiver) - Session não deve carregar o ';timeout=' do M6
    m7 = rtsp.recv_message()
    expect(m7, 'PLAY rtsp://', 'Session: ' + session + '\r\n')
    rtsp.send('RTSP/1.0 200 OK\r\nCSeq: 6\r\nSession: ' + session + '\r\n\r\n')
    print('[source] negociação M1-M7 concluída')

    # Streaming: pacotes RTP (payload MPEG-TS falso) para a client_port
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind((args.bind, 19000))
    seq = 0
    for _ in range(args.rtp_packets):
        header = bytes([0x80, 0x21, (seq >> 8) & 0xFF, seq & 0xFF]) + \
            (seq * 3003).to_bytes(4, 'big') + b'\x00\x00\x00\x01'
        udp.sendto(header + b'\x47' + b'\x00' * 187, (peer[0], client_port))
        seq += 1
        time.sleep(0.005)
    udp.close()
    print('[source] %d pacotes RTP enviados para %s:%d' % (seq, peer[0], client_port))

    # Keep-alive: GET_PARAMETER vazio, como o Windows faz periodicamente
    rtsp.send('GET_PARAMETER rtsp://localhost/wfd1.0 RTSP/1.0\r\nCSeq: 7\r\n\r\n')
    expect(rtsp.recv_message(), 'RTSP/1.0 200 OK', 'CSeq: 7')

    time.sleep(args.hold)

    # M8: trigger TEARDOWN -> sink responde 200 OK, envia TEARDOWN e fecha
    rtsp.set_parameter(8, M8)
    expect(rtsp.recv_message(), 'RTSP/1.0 200 OK', 'CSeq: 8')
    try:
        teardown = rtsp.recv_message(timeout=10)
    except ConnectionError:
        raise AssertionError('receiver fechou sem enviar TEARDOWN')
    expect(teardown, 'TEARDOWN rtsp://', 'Session: ' + session)
    cseq = [l for l in teardown.split('\r\n') if l.startswith('CSeq:')][0]
    rtsp.send('RTSP/1.0 200 OK\r\n' + cseq + '\r\n\r\n')

    conn.settimeout(10)
    try:
        rest = conn.recv(1024)
    except socket.timeout:
        raise AssertionError('receiver não fechou a conexão após TEARDOWN')
    except ConnectionResetError:
        rest = b''
    if rest:
        raise AssertionError('dados inesperados após TEARDOWN: %r' % rest)
    print('[source] receiver encerrou a sessão corretamente')
    conn.close()
    srv.close()
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--port', type=int, default=7236)
    p.add_argument('--rtp-packets', type=int, default=50)
    p.add_argument('--hold', type=float, default=1.0,
                   help='segundos de sessão ativa antes do TEARDOWN')
    p.add_argument('--accept-timeout', type=float, default=30)
    p.add_argument('--coalesce', action='store_true',
                   help='envia resposta M2 e pedido M3 juntos no mesmo segmento TCP')
    args = p.parse_args()
    try:
        return run(args)
    except (AssertionError, ConnectionError, socket.timeout) as e:
        print('[source] FALHA: %s' % e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
