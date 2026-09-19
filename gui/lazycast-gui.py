#!/usr/bin/env python3
"""LazyCast - painel gráfico (GTK3) para o Raspberry Pi.

Abas: Início (estado + "Ver telas"), Configurações e Diagnóstico.
A lógica (estado, configuração, saúde) fica em backend.py; aqui só há a interface.
"""
import os
import sys
import threading

import gi

gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backend  # noqa: E402

CSS = b"""
.card { background-color: @theme_base_color; border: 1px solid alpha(@theme_fg_color, 0.18);
        border-radius: 12px; padding: 16px; }
.big { font-size: 20pt; font-weight: bold; }
.title2 { font-size: 13pt; font-weight: bold; }
.muted { opacity: 0.7; }
.chip { background-color: alpha(@theme_selected_bg_color, 0.18); border-radius: 999px; padding: 4px 14px; font-weight: bold; }
.dot-ok { color: #2e9e4f; } .dot-warn { color: #d98e04; } .dot-bad { color: #d33f3f; } .dot-off { color: #8a8a8a; }
.warn-box { background-color: alpha(#d98e04, 0.16); border-radius: 8px; padding: 8px 12px; }
.section-title { font-weight: bold; font-size: 11pt; }
"""

STATE_TEXT = {
    'ready':     ('dot-ok',   'Pronto para conectar', 'Procure o nome abaixo na sua fonte (Windows: Win + K; celular: Smart View).'),
    'connected': ('dot-ok',   'Aparelho conectado',   'A imagem aparece nas telas abaixo. Use «Ver telas» para acompanhar.'),
    'starting':  ('dot-warn', 'Iniciando…',           'Criando a rede Wi-Fi Direct. Isso leva cerca de 30 segundos.'),
    'stopped':   ('dot-off',  'Parado',               'O LazyCast está desligado. Toque em «Iniciar».'),
    'error':     ('dot-bad',  'Com problema',         'O serviço falhou. Veja a aba Diagnóstico.'),
}


def label(text='', css=None, xalign=0.0, wrap=True, selectable=False):
    lb = Gtk.Label(label=text, xalign=xalign)
    lb.set_line_wrap(wrap)
    lb.set_selectable(selectable)
    if css:
        for c in css.split():
            lb.get_style_context().add_class(c)
    return lb


def card(child=None):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.get_style_context().add_class('card')
    if child is not None:
        box.pack_start(child, True, True, 0)
    return box


def run_async(fn, done=None):
    """Executa fn em thread e chama done(resultado) na thread da interface."""
    def worker():
        res = fn()
        if done:
            GLib.idle_add(done, res)
    threading.Thread(target=worker, daemon=True).start()


# ============================================================ Início
class HomePage(Gtk.Box):
    def __init__(self, app_win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self.win = app_win
        self.set_border_width(20)
        self.preview = None

        # cartão de estado
        st = Gtk.Box(spacing=14)
        self.dot = label('●', 'big dot-off', wrap=False)
        st.pack_start(self.dot, False, False, 0)
        txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.state_title = label('Verificando…', 'big')
        self.state_sub = label('', 'muted')
        txt.pack_start(self.state_title, False, False, 0)
        txt.pack_start(self.state_sub, False, False, 0)
        st.pack_start(txt, True, True, 0)
        self.pack_start(card(st), False, False, 0)

        # nome a procurar
        row = Gtk.Box(spacing=10)
        row.pack_start(label('Nome para procurar:', 'muted', wrap=False), False, False, 0)
        self.name_chip = label('raspberry', 'chip', wrap=False)
        row.pack_start(self.name_chip, False, False, 0)
        self.auth_lbl = label('', 'muted', wrap=False)
        row.pack_end(self.auth_lbl, False, False, 0)
        self.pack_start(row, False, False, 0)

        # telas
        self.screens_box = Gtk.Box(spacing=12, homogeneous=True)
        self.pack_start(self.screens_box, True, True, 0)
        self.screen_widgets = []

        # ações
        actions = Gtk.Box(spacing=10)
        self.btn_view = Gtk.Button(label='  Ver telas  ')
        self.btn_view.get_style_context().add_class('suggested-action')
        self.btn_view.connect('clicked', self.on_view)
        self.btn_toggle = Gtk.Button(label='Iniciar')
        self.btn_toggle.connect('clicked', self.on_toggle)
        self.btn_restart = Gtk.Button(label='Reiniciar')
        self.btn_restart.connect('clicked', self.on_restart)
        self.spinner = Gtk.Spinner()
        actions.pack_start(self.btn_view, False, False, 0)
        actions.pack_start(self.btn_toggle, False, False, 0)
        actions.pack_start(self.btn_restart, False, False, 0)
        actions.pack_start(self.spinner, False, False, 6)
        self.msg = label('', 'muted')
        actions.pack_start(self.msg, True, True, 0)
        self.pack_end(actions, False, False, 0)

        self.status = None

    def _ensure_screens(self, n):
        if len(self.screen_widgets) == n:
            return
        for w in self.screens_box.get_children():
            self.screens_box.remove(w)
        self.screen_widgets = []
        for i in range(n):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            title = label('Tela %d' % (i + 1), 'title2')
            state = label('Aguardando aparelho', 'muted')
            detail = label('', 'muted')
            box.pack_start(title, False, False, 0)
            box.pack_start(state, False, False, 0)
            box.pack_start(detail, False, False, 0)
            self.screens_box.pack_start(card(box), True, True, 0)
            self.screen_widgets.append((state, detail))
        self.screens_box.show_all()

    def update(self, st):
        self.status = st
        css, title, sub = STATE_TEXT.get(st['state'], STATE_TEXT['error'])
        ctx = self.dot.get_style_context()
        for c in ('dot-ok', 'dot-warn', 'dot-bad', 'dot-off'):
            ctx.remove_class(c)
        ctx.add_class(css)
        if st['state'] == 'connected':
            n = len(st['stations'])
            title = '%d aparelho%s conectado%s' % (n, '' if n == 1 else 's', '' if n == 1 else 's')
        self.state_title.set_text(title)
        self.state_sub.set_text(sub)
        self.name_chip.set_text(st['name'])
        self.auth_lbl.set_text('Conexão sem PIN' if st['auth'] != 'pin' else 'Conexão com PIN')
        self._ensure_screens(st['mode'])
        for slot, (state, detail) in zip(st['slots'], self.screen_widgets):
            if slot['streaming']:
                state.set_text('Recebendo imagem')
            elif slot['connected']:
                state.set_text('Conectado, aguardando imagem')
            else:
                state.set_text('Aguardando aparelho')
            detail.set_text(('De: %s' % slot['source']) if slot['source'] else '')
        running = st['state'] in ('ready', 'connected', 'starting')
        self.btn_toggle.set_label('Parar' if running else 'Iniciar')
        self.btn_view.set_sensitive(running)

    # ---- ações
    def _busy(self, text):
        self.spinner.start()
        self.msg.set_text(text)
        for b in (self.btn_toggle, self.btn_restart):
            b.set_sensitive(False)

    def _idle(self, text=''):
        self.spinner.stop()
        self.msg.set_text(text)
        for b in (self.btn_toggle, self.btn_restart):
            b.set_sensitive(True)
        self.win.refresh()

    def on_toggle(self, _b):
        running = self.status and self.status['state'] in ('ready', 'connected', 'starting')
        action = 'stop' if running else 'start'
        self._busy('Parando…' if running else 'Iniciando…')
        run_async(lambda: backend.service_action(action),
                  lambda r: self._idle('' if r[0] else 'Não foi possível: %s' % r[1]))

    def on_restart(self, _b):
        self._busy('Reiniciando… (cerca de 40 segundos)')
        run_async(lambda: backend.service_action('restart'),
                  lambda r: self._idle('' if r[0] else 'Não foi possível: %s' % r[1]))

    def on_view(self, _b):
        if self.preview is None or not self.preview.get_visible():
            self.preview = PreviewWindow(self.win, self)
        self.preview.present()


# ============================================================ Prévia das telas
class PreviewWindow(Gtk.Window):
    THUMB_W, THUMB_H = 420, 236

    def __init__(self, parent, home):
        super().__init__(title='Telas recebidas')
        self.set_transient_for(parent)
        self.home = home
        self.set_border_width(16)
        self.set_default_size(900, 340)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(outer)
        self.row = Gtk.Box(spacing=14, homogeneous=True)
        outer.pack_start(self.row, True, True, 0)
        self.items = []
        n = home.status['mode'] if home.status else 1
        for i in range(n):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            stack = Gtk.Stack()
            stack.set_size_request(self.THUMB_W, self.THUMB_H)
            ph = label('Aguardando aparelho…', 'muted', xalign=0.5)
            ph.set_valign(Gtk.Align.CENTER)
            img = Gtk.Image()
            stack.add_named(ph, 'wait')
            stack.add_named(img, 'img')
            cap = label('Tela %d' % (i + 1), 'title2', xalign=0.5)
            box.pack_start(card(stack), True, True, 0)
            box.pack_start(cap, False, False, 0)
            self.row.pack_start(box, True, True, 0)
            self.items.append((stack, img, cap))
        self.note = label('Prévia atualizada a cada segundo. Com monitores nos HDMI, cada tela vai em '
                          'tela cheia no seu monitor.', 'muted')
        outer.pack_start(self.note, False, False, 0)
        self.timer = GLib.timeout_add(1000, self.tick)
        self.connect('destroy', lambda *_: GLib.source_remove(self.timer) if self.timer else None)
        self.show_all()
        self.tick()

    def tick(self):
        st = self.home.status
        regions = backend.layout_regions(n=len(self.items))
        for i, (stack, img, cap) in enumerate(self.items):
            slot = st['slots'][i] if st and i < len(st['slots']) else None
            cap.set_text('Tela %d%s' % (i + 1, (' — ' + slot['source']) if slot and slot['source'] else ''))
            if not (slot and slot['streaming'] and i < len(regions)):
                stack.set_visible_child_name('wait')
                continue
            data = backend.grab(regions[i])
            if not data:
                continue
            try:
                loader = GdkPixbuf.PixbufLoader()
                loader.write(data)
                loader.close()
                pb = loader.get_pixbuf()
                scale = min(self.THUMB_W / pb.get_width(), self.THUMB_H / pb.get_height())
                pb = pb.scale_simple(int(pb.get_width() * scale), int(pb.get_height() * scale), GdkPixbuf.InterpType.BILINEAR)
                img.set_from_pixbuf(pb)
                stack.set_visible_child_name('img')
            except GLib.Error:
                pass
        return True


# ============================================================ Configurações
class SettingsPage(Gtk.ScrolledWindow):
    def __init__(self, app_win):
        super().__init__()
        self.win = app_win
        self.loading = False
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        outer.set_border_width(20)
        self.add(outer)

        # Identificação
        self.name = Gtk.Entry()
        self.name.connect('changed', self.mark_dirty)
        outer.pack_start(self.section('Nome do display',
                                      'É o nome que aparece no Windows e no celular.', self.name), False, False, 0)

        # Telas
        self.r1 = Gtk.RadioButton.new_with_label_from_widget(None, 'Uma tela')
        self.r2 = Gtk.RadioButton.new_with_label_from_widget(self.r1, 'Duas telas (duas fontes ao mesmo tempo)')
        for r in (self.r1, self.r2):
            r.connect('toggled', self.mark_dirty)
        rb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        rb.pack_start(self.r1, False, False, 0)
        rb.pack_start(self.r2, False, False, 0)
        outer.pack_start(self.section('Telas',
                                      'No modo duas telas, a 1ª fonte a conectar vai para a Tela 1 e a 2ª para a Tela 2.', rb),
                         False, False, 0)

        # Segurança
        self.sw_pin = Gtk.Switch()
        self.sw_pin.set_halign(Gtk.Align.START)
        self.sw_pin.connect('notify::active', self.on_pin_toggle)
        self.pin_entry = Gtk.Entry()
        self.pin_entry.set_max_length(8)
        self.pin_entry.set_width_chars(10)
        self.pin_entry.connect('changed', self.mark_dirty)
        self.btn_newpin = Gtk.Button(label='Gerar novo')
        self.btn_newpin.connect('clicked', lambda *_: self.pin_entry.set_text(backend.generate_pin()))
        pinrow = Gtk.Box(spacing=8)
        pinrow.pack_start(label('PIN:', wrap=False), False, False, 0)
        pinrow.pack_start(self.pin_entry, False, False, 0)
        pinrow.pack_start(self.btn_newpin, False, False, 0)
        self.pin_row = pinrow
        self.warn = label('Sem PIN, qualquer aparelho ao alcance do Wi-Fi do Pi pode espelhar na tela.', 'warn-box')
        sec = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        sw_row = Gtk.Box(spacing=10)
        sw_row.pack_start(self.sw_pin, False, False, 0)
        sw_row.pack_start(label('Exigir PIN para conectar', wrap=False), False, False, 0)
        sec.pack_start(sw_row, False, False, 0)
        sec.pack_start(self.pin_row, False, False, 0)
        sec.pack_start(self.warn, False, False, 0)
        outer.pack_start(self.section('Segurança', 'Recomendado se o Pi ficar em local público.', sec), False, False, 0)

        # Qualidade
        self.q60 = Gtk.RadioButton.new_with_label_from_widget(None, 'Mais fluido (1080p, 60 quadros)')
        self.q50 = Gtk.RadioButton.new_with_label_from_widget(self.q60, 'Mais estável (1080p, 50 quadros)')
        for r in (self.q60, self.q50):
            r.connect('toggled', self.mark_dirty)
        qb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        qb.pack_start(self.q60, False, False, 0)
        qb.pack_start(self.q50, False, False, 0)
        outer.pack_start(self.section('Qualidade da imagem',
                                      'Se a imagem travar, escolha «Mais estável».', qb), False, False, 0)

        # Avançado
        self.sw_kb = Gtk.Switch()
        self.sw_kb.connect('notify::active', self.mark_dirty)
        self.sw_boot = Gtk.Switch()
        self.sw_boot.connect('notify::active', self.mark_dirty)
        adv = Gtk.Grid(column_spacing=12, row_spacing=10)
        adv.attach(self.sw_boot, 0, 0, 1, 1)
        adv.attach(label('Iniciar junto com o Raspberry', wrap=False), 1, 0, 1, 1)
        adv.attach(self.sw_kb, 0, 1, 1, 1)
        adv.attach(label('Usar mouse e teclado do Pi na fonte', wrap=False), 1, 1, 1, 1)
        outer.pack_start(self.section('Avançado', '', adv), False, False, 0)

        # rodapé
        foot = Gtk.Box(spacing=10)
        self.btn_save = Gtk.Button(label='Salvar e aplicar')
        self.btn_save.get_style_context().add_class('suggested-action')
        self.btn_save.connect('clicked', self.on_save)
        self.btn_discard = Gtk.Button(label='Descartar')
        self.btn_discard.connect('clicked', lambda *_: self.load())
        self.spinner = Gtk.Spinner()
        self.msg = label('', 'muted')
        foot.pack_start(self.btn_save, False, False, 0)
        foot.pack_start(self.btn_discard, False, False, 0)
        foot.pack_start(self.spinner, False, False, 4)
        foot.pack_start(self.msg, True, True, 0)
        outer.pack_start(foot, False, False, 0)
        self.load()

    def section(self, title, hint, widget):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.pack_start(label(title, 'section-title'), False, False, 0)
        if hint:
            box.pack_start(label(hint, 'muted'), False, False, 0)
        box.pack_start(widget, False, False, 0)
        return card(box)

    # ---- estado
    def load(self):
        self.loading = True
        cfg = backend.load_config()
        self.cfg = cfg
        self.name.set_text(cfg['DISPLAY1_NAME'])
        (self.r2 if cfg['DISPLAY_MODE'] == '2' else self.r1).set_active(True)
        pin_on = cfg['LAZYCAST_AUTH'] == 'pin'
        self.sw_pin.set_active(pin_on)
        self.pin_entry.set_text(cfg['LAZYCAST_PIN'])
        (self.q50 if cfg['DISABLE_1920_1080_60FPS'] == '1' else self.q60).set_active(True)
        self.sw_kb.set_active(cfg['ENABLE_MOUSE_KEYBOARD'] == '1')
        self.sw_boot.set_active(backend.service_enabled())
        self._pin_visibility()
        self.loading = False
        self.btn_save.set_sensitive(False)
        self.btn_discard.set_sensitive(False)
        self.msg.set_text('')

    def _pin_visibility(self):
        on = self.sw_pin.get_active()
        self.pin_row.set_visible(on)
        self.warn.set_visible(not on)

    def on_pin_toggle(self, *_):
        self._pin_visibility()
        if self.sw_pin.get_active() and not self.pin_entry.get_text():
            self.pin_entry.set_text(backend.generate_pin())
        self.mark_dirty()

    def mark_dirty(self, *_):
        if self.loading:
            return
        self.btn_save.set_sensitive(True)
        self.btn_discard.set_sensitive(True)
        self.msg.set_text('Alterações ainda não aplicadas')

    def validate(self):
        if not self.name.get_text().strip():
            return 'Digite um nome para o display.'
        if self.sw_pin.get_active() and not backend.wps_checksum_ok(self.pin_entry.get_text()):
            return 'PIN inválido. Use 8 dígitos válidos (toque em «Gerar novo»).'
        return None

    def on_save(self, _b):
        err = self.validate()
        if err:
            self.msg.set_text(err)
            return
        updates = {
            'DISPLAY1_NAME': self.name.get_text().strip().replace('"', ''),
            'DISPLAY_MODE': '2' if self.r2.get_active() else '1',
            'LAZYCAST_AUTH': 'pin' if self.sw_pin.get_active() else 'pbc',
            'DISABLE_1920_1080_60FPS': '1' if self.q50.get_active() else '0',
            'ENABLE_MOUSE_KEYBOARD': '1' if self.sw_kb.get_active() else '0',
        }
        if self.sw_pin.get_active():
            updates['LAZYCAST_PIN'] = self.pin_entry.get_text()
        boot = self.sw_boot.get_active()
        self.spinner.start()
        self.btn_save.set_sensitive(False)
        self.msg.set_text('Aplicando… reiniciando o serviço (cerca de 40 segundos)')

        def work():
            try:
                backend.save_config(updates)
            except OSError as e:
                return False, 'Não foi possível gravar a configuração: %s' % e
            ok1, out1 = backend.service_action('enable' if boot else 'disable')
            ok2, out2 = backend.service_action('restart')
            return ok2, out2

        def done(res):
            self.spinner.stop()
            ok, out = res
            self.msg.set_text('Aplicado.' if ok else 'Falhou: %s' % out)
            self.btn_discard.set_sensitive(False)
            self.win.refresh()
        run_async(work, done)


# ============================================================ Diagnóstico
class DiagPage(Gtk.Box):
    def __init__(self, app_win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.win = app_win
        self.set_border_width(20)
        self.list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.pack_start(card(self.list), False, False, 0)
        row = Gtk.Box(spacing=10)
        b1 = Gtk.Button(label='Atualizar')
        b1.connect('clicked', lambda *_: self.refresh())
        b2 = Gtk.Button(label='Copiar relatório')
        b2.connect('clicked', self.on_copy)
        self.msg = label('', 'muted')
        row.pack_start(b1, False, False, 0)
        row.pack_start(b2, False, False, 0)
        row.pack_start(self.msg, True, True, 6)
        self.pack_start(row, False, False, 0)
        exp = Gtk.Expander(label='Log do serviço')
        self.log = Gtk.TextView()
        self.log.set_editable(False)
        self.log.set_monospace(True)
        sw = Gtk.ScrolledWindow()
        sw.set_min_content_height(160)
        sw.add(self.log)
        exp.add(sw)
        exp.connect('notify::expanded', lambda *_: self.load_log())
        self.exp = exp
        self.pack_start(exp, True, True, 0)

    def refresh(self):
        self.msg.set_text('Verificando…')
        run_async(backend.health_checks, self.show)

    def show(self, checks):
        for w in self.list.get_children():
            self.list.remove(w)
        for name, ok, hint in checks:
            row = Gtk.Box(spacing=10)
            row.pack_start(label('✔' if ok else '✖', 'dot-ok' if ok else 'dot-bad', wrap=False), False, False, 0)
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            col.pack_start(label(name), False, False, 0)
            if hint:
                col.pack_start(label(hint, 'muted'), False, False, 0)
            row.pack_start(col, True, True, 0)
            self.list.pack_start(row, False, False, 0)
        self.list.show_all()
        self.msg.set_text('')

    def load_log(self):
        if self.exp.get_expanded():
            run_async(lambda: backend.read_log(200), lambda t: self.log.get_buffer().set_text(t))

    def on_copy(self, _b):
        def done(text):
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
            self.msg.set_text('Relatório copiado. Cole na conversa para pedir ajuda.')
        run_async(backend.report_text, done)


# ============================================================ Janela principal
class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title='LazyCast')
        self.set_default_size(760, 600)
        self.set_icon_name('video-display')
        hb = Gtk.HeaderBar()
        hb.set_show_close_button(True)
        hb.props.title = 'LazyCast'
        self.set_titlebar(hb)
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        switcher = Gtk.StackSwitcher()
        switcher.set_stack(self.stack)
        hb.set_custom_title(switcher)
        self.home = HomePage(self)
        self.settings = SettingsPage(self)
        self.diag = DiagPage(self)
        self.stack.add_titled(self.home, 'home', 'Início')
        self.stack.add_titled(self.settings, 'settings', 'Configurações')
        self.stack.add_titled(self.diag, 'diag', 'Diagnóstico')
        self.stack.connect('notify::visible-child-name', self.on_page)
        self.add(self.stack)
        self._busy = False
        self.refresh()
        GLib.timeout_add_seconds(2, self.tick)
        self.diag.refresh()

    def on_page(self, *_):
        if self.stack.get_visible_child_name() == 'diag':
            self.diag.refresh()

    def tick(self):
        self.refresh()
        return True

    def refresh(self):
        if self._busy:
            return
        self._busy = True

        def done(st):
            self._busy = False
            self.home.update(st)
        run_async(backend.get_status, done)


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='br.lazycast.Gui')

    def do_activate(self):
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        win = self.props.active_window or MainWindow(self)
        win.show_all()
        win.settings._pin_visibility()
        win.present()


if __name__ == '__main__':
    sys.exit(App().run(sys.argv))
