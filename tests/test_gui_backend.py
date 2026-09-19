#!/usr/bin/env python3
"""Testes da camada de dados da GUI (gui/backend.py) com comandos simulados. Sem GTK/hardware."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'gui'))
import backend  # noqa: E402


class FakeRun:
    """Substitui backend.run/backend.sudo: mapeia prefixos de comando -> (código, saída)."""

    def __init__(self, table):
        self.table = table
        self.calls = []

    def __call__(self, cmd, timeout=6):
        if cmd and cmd[0] == 'sudo':
            cmd = [c for c in cmd if c != '-n'][1:]
        self.calls.append(cmd)
        for prefix, result in self.table.items():
            if ' '.join(cmd).startswith(prefix):
                return result
        return 1, ''


def install_fake(table):
    fake = FakeRun(table)
    backend.run = fake
    backend.sudo = lambda cmd, timeout=8: fake(['sudo', '-n'] + cmd, timeout)
    return fake


class ConfigTests(unittest.TestCase):
    def test_parse_config_ignora_comentarios_e_aspas(self):
        cfg = backend.parse_config('# c\nDISPLAY1_NAME="Sala 1"\nDISPLAY_MODE=2\n  X_Y=abc\n')
        self.assertEqual(cfg['DISPLAY1_NAME'], 'Sala 1')
        self.assertEqual(cfg['DISPLAY_MODE'], '2')
        self.assertEqual(cfg['X_Y'], 'abc')

    def test_update_preserva_comentarios_e_ordem(self):
        text = '# titulo\nDISPLAY1_NAME="a"\n# meio\nDISPLAY_MODE=1\n'
        out = backend.update_config_text(text, {'DISPLAY1_NAME': 'b', 'NOVA': 'x'})
        self.assertIn('# titulo', out)
        self.assertIn('# meio', out)
        self.assertIn('DISPLAY1_NAME="b"', out)
        self.assertIn('DISPLAY_MODE=1', out)
        self.assertTrue(out.rstrip().endswith('NOVA="x"'))
        self.assertEqual(out.count('DISPLAY1_NAME'), 1)

    def test_save_e_load_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, 'c.conf')
            open(p, 'w').write('DISPLAY1_NAME="x"\nLAZYCAST_AUTH="pbc"\n')
            backend.save_config({'LAZYCAST_AUTH': 'pin', 'LAZYCAST_PIN': '12345670'}, p)
            cfg = backend.load_config(p)
            self.assertEqual(cfg['LAZYCAST_AUTH'], 'pin')
            self.assertEqual(cfg['LAZYCAST_PIN'], '12345670')
            self.assertEqual(cfg['DISPLAY1_NAME'], 'x')

    def test_load_config_sem_arquivo_usa_padroes(self):
        cfg = backend.load_config('/nao/existe.conf')
        self.assertEqual(cfg['LAZYCAST_AUTH'], 'pbc')


class PinTests(unittest.TestCase):
    def test_pin_conhecido_valido(self):
        self.assertTrue(backend.wps_checksum_ok('12345670'))

    def test_pin_invalido(self):
        for bad in ('12345671', '1234567', 'abcdefgh', '', None, '123456700'):
            self.assertFalse(backend.wps_checksum_ok(bad), bad)

    def test_gerados_sao_validos(self):
        for _ in range(200):
            self.assertTrue(backend.wps_checksum_ok(backend.generate_pin()))


class StatusTests(unittest.TestCase):
    CFG = dict(backend.DEFAULTS, DISPLAY_MODE='2', DISPLAY1_NAME='raspberry')

    def test_parado(self):
        install_fake({'systemctl is-active': (3, 'inactive\n')})
        st = backend.get_status(self.CFG)
        self.assertEqual(st['state'], 'stopped')
        self.assertEqual(len(st['slots']), 2)

    def test_erro_quando_failed(self):
        install_fake({'systemctl is-active': (3, 'failed\n')})
        self.assertEqual(backend.get_status(self.CFG)['state'], 'error')

    def test_iniciando_sem_grupo(self):
        install_fake({'systemctl is-active': (0, 'active\n'), 'iw dev': (0, 'phy#0\n\tInterface wlan0\n')})
        self.assertEqual(backend.get_status(self.CFG)['state'], 'starting')

    def test_pronto_sem_aparelhos(self):
        install_fake({'systemctl is-active': (0, 'active\n'),
                      'iw dev p2p': (0, ''),
                      'iw dev': (0, '\tInterface wlan0\n\tInterface p2p-wlan0-5\n'),
                      'busybox dumpleases': (0, 'Mac Address       IP Address      Host Name           Expires in\n')})
        st = backend.get_status(self.CFG)
        self.assertEqual(st['state'], 'ready')
        self.assertEqual(st['group'], 'p2p-wlan0-5')
        self.assertFalse(any(s['connected'] for s in st['slots']))

    def test_dois_aparelhos_mapeados_por_ip(self):
        leases = ('Mac Address       IP Address      Host Name           Expires in\n'
                  '9a:d7:42:d1:82:84 192.168.173.80  S25-Ultra           02:33:54\n'
                  '5e:cd:5b:44:66:a0 192.168.173.81  GUSTAVO-PC          02:33:50\n')
        stations = ('Station 9a:d7:42:d1:82:84 (on p2p-wlan0-5)\n\tinactive time: 0 ms\n'
                    'Station 5e:cd:5b:44:66:a0 (on p2p-wlan0-5)\n\tinactive time: 4 ms\n')
        install_fake({'systemctl is-active': (0, 'active\n'),
                      'iw dev p2p-wlan0-5 station dump': (0, stations),
                      'iw dev': (0, '\tInterface p2p-wlan0-5\n'),
                      'busybox dumpleases': (0, leases),
                      'pgrep -f rtp://0.0.0.0:1028': (0, '1\n'),
                      'pgrep -f rtp://0.0.0.0:1030': (1, '')})
        st = backend.get_status(self.CFG)
        self.assertEqual(st['state'], 'connected')
        self.assertEqual(st['slots'][0]['source'], 'S25-Ultra')
        self.assertTrue(st['slots'][0]['streaming'])
        self.assertEqual(st['slots'][1]['source'], 'GUSTAVO-PC')
        self.assertFalse(st['slots'][1]['streaming'])

    def test_slot_ip(self):
        self.assertEqual(backend.slot_ip(self.CFG, 0), '192.168.173.80')
        self.assertEqual(backend.slot_ip(self.CFG, 1), '192.168.173.81')


class HealthTests(unittest.TestCase):
    def test_tudo_ok(self):
        install_fake({'systemctl is-active': (0, 'active\n'),
                      'wpa_cli interface': (0, 'Available interfaces:\np2p-dev-wlan0\nwlan0\n'),
                      'iw dev': (0, 'Interface p2p-wlan0-5\n'),
                      'wpa_cli -i p2p-dev-wlan0 get wifi_display': (0, '1\n'),
                      'pgrep': (0, '1\n'),
                      'ps -o stat= -C NetworkManager': (0, 'Tsl\n')})
        res = backend.health_checks(dict(backend.DEFAULTS))
        self.assertTrue(all(ok for _, ok, _ in res), res)

    def test_wfd_desligado_e_dica(self):
        install_fake({'systemctl is-active': (0, 'active\n'),
                      'wpa_cli interface': (0, 'p2p-dev-wlan0\n'),
                      'iw dev': (0, 'Interface p2p-wlan0-5\n'),
                      'wpa_cli -i p2p-dev-wlan0 get wifi_display': (0, '0\n'),
                      'pgrep': (0, '1\n'), 'ps -o stat= -C NetworkManager': (0, 'Tsl\n')})
        res = {label: (ok, hint) for label, ok, hint in backend.health_checks(dict(backend.DEFAULTS))}
        ok, hint = res['Anúncio Miracast (WFD) ligado']
        self.assertFalse(ok)
        self.assertIn('Reinicie', hint)

    def test_p2p_indisponivel(self):
        install_fake({'systemctl is-active': (0, 'active\n'), 'wpa_cli interface': (0, 'wlan0\n')})
        res = {label: ok for label, ok, _ in backend.health_checks(dict(backend.DEFAULTS))}
        self.assertFalse(res['Wi-Fi Direct (P2P) disponível'])


class SnapshotTests(unittest.TestCase):
    def test_pega_o_mais_recente_e_limpa_os_antigos(self):
        import time
        d = tempfile.mkdtemp()
        for i, name in enumerate(('lc1028-00001.jpg', 'lc1028-00002.jpg')):
            with open(os.path.join(d, name), 'wb') as f:
                f.write(b'frame%d' % i)
            os.utime(os.path.join(d, name), (time.time() + i, time.time() + i))
        with open(os.path.join(d, 'lc1030-00001.jpg'), 'wb') as f:
            f.write(b'outra-porta')
        self.assertEqual(backend.latest_snapshot(d, '1028'), b'frame1')
        self.assertEqual(sorted(os.listdir(d)), ['lc1030-00001.jpg'])

    def test_sem_arquivos(self):
        self.assertIsNone(backend.latest_snapshot(tempfile.mkdtemp(), '1028'))

    def test_sem_socket_devolve_none(self):
        self.assertIsNone(backend.request_snapshot('1028', wait=0.1, directory=tempfile.mkdtemp()))

    def test_pasta_privada_usa_xdg_runtime_dir(self):
        old = os.environ.get('XDG_RUNTIME_DIR')
        os.environ['XDG_RUNTIME_DIR'] = '/run/user/1000'
        try:
            self.assertEqual(backend.snap_dir(), os.path.join('/run/user/1000', 'lazycast'))
        finally:
            if old is None:
                os.environ.pop('XDG_RUNTIME_DIR')
            else:
                os.environ['XDG_RUNTIME_DIR'] = old


if __name__ == '__main__':
    unittest.main(verbosity=1)
