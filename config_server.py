#!/usr/bin/env python3
"""Servidor HTTP pequeno (biblioteca padrão do Python, sem dependência nova) que expõe as configurações
do LazyCast na rede local, para o programa Windows (windows/lazycast_windows.py) buscar e gravar sem
precisar de SSH nem senha.

Mesmo nível de exposição que o resto do projeto já tem hoje: só na rede local (Wi-Fi/cabo da casa),
sem autenticação — igual ao fluxo de vídeo e ao Miracast, que também não pedem senha na rede.

Rotas:
  GET  /api/config   -> JSON com o que aparece na aba Configurações do painel do Pi
  POST /api/config   -> JSON com as mesmas chaves; grava e reinicia o serviço (igual ao "Salvar e aplicar")
  GET  /api/status   -> JSON com backend.get_status() (para o Windows mostrar "conectado"/nome da rede)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, 'gui')
import backend  # noqa: E402

PORTA = 8765

# Campos da aba Configurações do painel (gui/lazycast-gui.py) que o programa Windows pode ler/gravar.
CAMPOS = ('DISPLAY1_NAME', 'DISPLAY_MODE', 'LAZYCAST_AUTH', 'LAZYCAST_PIN', 'SCREEN1_SOURCE', 'SCREEN2_SOURCE')


def config_atual():
    cfg = backend.load_config()
    return {k: cfg.get(k, '') for k in CAMPOS}


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        corpo = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(corpo)))
        # Só para o programa Windows local (chamada direta, não navegador); CORS liberado por simplicidade.
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(corpo)

    def do_GET(self):
        if self.path == '/api/config':
            self._json(200, config_atual())
        elif self.path == '/api/status':
            try:
                self._json(200, backend.get_status())
            except Exception as e:
                self._json(500, {'erro': str(e)})
        else:
            self._json(404, {'erro': 'rota desconhecida'})

    def do_POST(self):
        if self.path != '/api/config':
            self._json(404, {'erro': 'rota desconhecida'})
            return
        try:
            tam = int(self.headers.get('Content-Length', 0))
            dados = json.loads(self.rfile.read(tam) or b'{}')
        except (ValueError, json.JSONDecodeError):
            self._json(400, {'erro': 'JSON inválido'})
            return
        updates = {}
        for k in CAMPOS:
            if k in dados:
                updates[k] = str(dados[k])
        if 'DISPLAY1_NAME' in updates and not backend.valid_display_name(updates['DISPLAY1_NAME']):
            self._json(400, {'erro': 'Nome da rede inválido (1-32 letras, números, espaço, . _ -).'})
            return
        if updates.get('LAZYCAST_AUTH') == 'pin' and not backend.wps_checksum_ok(updates.get('LAZYCAST_PIN', '')):
            self._json(400, {'erro': 'PIN inválido (8 dígitos com checksum WPS).'})
            return
        backend.save_config(updates)
        ok, msg = backend.service_action('restart')
        self._json(200, {'ok': ok, 'mensagem': msg, 'config': config_atual()})

    def log_message(self, fmt, *args):
        pass  # silencioso (o serviço já tem seu próprio log)


def main():
    servidor = ThreadingHTTPServer(('0.0.0.0', PORTA), Handler)
    print(f'Servidor de configuração do LazyCast em http://0.0.0.0:{PORTA}')
    servidor.serve_forever()


if __name__ == '__main__':
    main()
