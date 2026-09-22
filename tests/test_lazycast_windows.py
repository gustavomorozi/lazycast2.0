#!/usr/bin/env python3
"""Testes da logica pura de windows/lazycast_windows.py (o programa Windows, reescrito de PowerShell
para Python). So roda no Windows: o modulo usa ctypes.windll (API do Windows) so no import."""
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'windows'))

if not sys.platform.startswith('win'):
    print('lazycast_windows.py e so para Windows (ctypes.windll); pulando estes testes.')
    sys.exit(0)

import lazycast_windows as lc  # noqa: E402


class IpTests(unittest.TestCase):
    def test_ip_unico_valido(self):
        self.assertTrue(lc.validar_ip('192.168.0.43'))

    def test_dois_ips_separados_por_virgula(self):
        self.assertTrue(lc.validar_ip('192.168.0.50,192.168.0.43'))
        self.assertTrue(lc.validar_ip('192.168.0.50; 192.168.0.43'))

    def test_ip_invalido(self):
        for ruim in ('abc', '1.2.3', '1.2.3.4.5', '', '1.2.3.4 rm -rf'):
            self.assertFalse(lc.validar_ip(ruim), ruim)

    def test_escolhe_o_primeiro_ip_que_responde(self):
        chamadas = []

        def fake_ping(ip):
            chamadas.append(ip)
            return ip == '192.168.0.43'
        antigo = lc._pingar
        lc._pingar = fake_ping
        try:
            self.assertEqual(lc.escolher_pi_que_responde('192.168.0.50,192.168.0.43'), '192.168.0.43')
            self.assertEqual(chamadas, ['192.168.0.50', '192.168.0.43'])
        finally:
            lc._pingar = antigo

    def test_nenhum_responde_usa_o_primeiro(self):
        antigo = lc._pingar
        lc._pingar = lambda ip: False
        try:
            self.assertEqual(lc.escolher_pi_que_responde('192.168.0.50,192.168.0.43'), '192.168.0.50')
        finally:
            lc._pingar = antigo


class EncoderTests(unittest.TestCase):
    def test_qsv_sem_b_frames_e_bitrate_certo(self):
        args = lc._args_encoder('qsv', 30, '3M')
        self.assertIn('h264_qsv', args)
        self.assertEqual(args[args.index('-b:v') + 1], '3M')
        self.assertEqual(args[args.index('-g') + 1], '30')
        self.assertIn('-bf', args)
        self.assertEqual(args[args.index('-bf') + 1], '0')

    def test_x264_tem_zerolatency(self):
        args = lc._args_encoder('x264', 30, '3M')
        self.assertIn('libx264', args)
        self.assertIn('zerolatency', args)

    def test_nvenc_tune_ll(self):
        args = lc._args_encoder('nvenc', 30, '3M')
        self.assertIn('h264_nvenc', args)
        self.assertIn('ll', args)


class DriverHashTests(unittest.TestCase):
    def test_hash_esperado_tem_64_hex(self):
        self.assertRegex(lc.DRV_SHA256, r'^[0-9a-f]{64}$')

    def test_baixar_driver_recusa_arquivo_com_hash_errado(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            falso = Path(d) / 'falso.zip'
            falso.write_bytes(b'nao e o driver de verdade')
            inf, devcon = lc.baixar_driver(zip_local=str(falso), log=lambda *_: None)
            self.assertIsNone(inf)
            self.assertIsNone(devcon)


class DescobertaTests(unittest.TestCase):
    def test_meu_ip_parece_um_ip(self):
        self.assertTrue(lc.validar_ip(lc._meu_ip()))


class ConfigPiMappingTests(unittest.TestCase):
    """Mapeamento texto-do-combo <-> valor gravado no lazycast-config.conf (seção 4 da janela)."""

    def test_fontes_ida_e_volta(self):
        for raw in ('auto', 'stream:5004', 'stream:5006'):
            idx = lc.App._FONTES_RAW.index(raw)
            txt = lc.App._FONTES_TXT[idx]
            self.assertEqual(lc.App._FONTES_RAW[lc.App._FONTES_TXT.index(txt)], raw)

    def test_auth_ida_e_volta(self):
        for raw in ('pbc', 'pin'):
            idx = lc.App._AUTH_RAW.index(raw)
            txt = lc.App._AUTH_TXT[idx]
            self.assertEqual(lc.App._AUTH_RAW[lc.App._AUTH_TXT.index(txt)], raw)

    def test_listas_mesmo_tamanho(self):
        self.assertEqual(len(lc.App._FONTES_RAW), len(lc.App._FONTES_TXT))
        self.assertEqual(len(lc.App._AUTH_RAW), len(lc.App._AUTH_TXT))

    def test_campos_config_pi_batem_com_o_servidor(self):
        # config_server.py (no Pi) expõe exatamente estes campos; se um lado mudar sem o outro, a janela
        # buscaria/gravaria campos que o servidor ignora silenciosamente.
        import re
        servidor = (Path(__file__).resolve().parent.parent / 'config_server.py').read_text(encoding='utf-8')
        m = re.search(r"CAMPOS = \(([^)]*)\)", servidor)
        campos_servidor = set(re.findall(r"'([A-Z0-9_]+)'", m.group(1)))
        campos_janela = set(lc.CAMPOS_CONFIG_PI)
        self.assertEqual(campos_servidor, campos_janela)


if __name__ == '__main__':
    unittest.main()
