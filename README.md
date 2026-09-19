# LazyCast 2.0 — Receptor Miracast para Raspberry Pi 5

Receptor de display sem fio (Miracast / Wi-Fi Display) simples, com **suporte a Dual Display** (duas saídas HDMI) e execução como **serviço systemd**. Fontes suportadas: Windows 8.1/10/11 e Android.

> Baseado no [LazyCast](https://github.com/homeworkc/lazycast) de Hsun-Wei Cho (homeworkc), licença GPL-3.0. A adaptação para Raspberry Pi 5, o modo dual display, o instalador e o serviço foram desenvolvidos por Gustavo Morozi.

## Sumário

- [Compatibilidade](#compatibilidade)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Uso](#uso)
- [Configuração](#configuração)
- [Serviço systemd](#serviço-systemd)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Testes](#testes)
- [Solução de problemas](#solução-de-problemas)
- [Limitações conhecidas](#limitações-conhecidas)
- [Documentação adicional](#documentação-adicional)
- [Licença](#licença)

## Compatibilidade

Esta versão suporta **somente o Raspberry Pi 5** (Raspberry Pi OS Bookworm 64-bit, driver KMS `vc4-kms-v3d`) e usa o **VLC** como player. O `install.sh` recusa outros modelos (use `--force` por sua conta e risco).

## Requisitos

- Raspberry Pi 5 com Raspberry Pi OS Bookworm (64-bit) e ambiente gráfico.
- Pacotes (`vlc busybox wpasupplicant libx11-dev build-essential python3 python3-evdev libnotify-bin`): o `install.sh` instala automaticamente; é preciso apenas internet.
- `wpa_cli` precisa enxergar a interface `p2p-dev-wlan0` (`sudo wpa_cli interface`). Se a lista vier vazia, o Wi-Fi P2P não está acessível ao LazyCast (comum quando o NetworkManager controla o `wpa_supplicant`).
- **Adaptador USB (dual display):** funciona com qualquer adaptador USB Wi-Fi **cujo driver liste `P2P-client` e `P2P-GO`** (confira: `iw phy | grep -A9 "Supported interface modes"`), em qualquer porta USB. A escolha é por capacidade, não pelo nome (`wlan1`/`wlx…`), e a ordem é estável (interno primeiro, depois por MAC). Para fixar qual adaptador atende cada display: `DISPLAY1_P2P_DEV`/`DISPLAY2_P2P_DEV` no `lazycast-config.conf` (nome da interface ou MAC). Chips sem P2P, como o Ralink RT5370 (`rt2800usb`), **não servem**; o instalador mostra a tabela de adaptadores e avisa.
- **Dual display:** o Wi-Fi interno sustenta **um** grupo P2P por vez. Para dois displays independentes é necessário **um segundo adaptador Wi-Fi USB com suporte a P2P**; a instância *N* usa a *N*-ésima interface `p2p-dev-*`.

## Instalação

```bash
sudo apt install git
git clone https://github.com/gustavomorozi/lazycast2.0
cd lazycast2.0
sudo ./install.sh
```

O instalador **instala sozinho todas as dependências** (via `apt`), ajusta permissões, configura o HDMI (dual display no Pi 5) e instala o serviço systemd. Para instalar sem nenhuma pergunta (padrões: single display, VLC): `sudo ./install.sh --yes` (use `--no-service` para não instalar o serviço). Ele detecta o modelo do Pi e pergunta modo (single/dual), nomes dos displays, player e saída de áudio, gera `lazycast-config.conf`, compila `control/` e, opcionalmente, instala o serviço systemd.

No modo dual, o instalador já executa o `setup-hdmi.sh` (garante o driver KMS; reinicie ao final). Para reexecutar manualmente:

```bash
sudo ./setup-hdmi.sh
```

## Uso

Execução manual (sem serviço):

```bash
./all.sh          # Single display
./all-dual.sh     # Dual display
```

**Conexão sem PIN (padrão):** o Pi anuncia só o método "botão" (WPS PBC) e mantém o botão ativo, então Windows e Android conectam sem digitar nada. Atenção: qualquer aparelho ao alcance do Wi-Fi do Pi pode espelhar na tela. Para exigir PIN, defina `LAZYCAST_AUTH=pin` em `lazycast-config.conf` (o PIN aleatório fica em `LAZYCAST_PIN`) e rode `sudo systemctl restart lazycast`.

Aguarde a mensagem `The display is ready` e procure o nome do display na fonte (Windows: *Win + K*; Android: *Transmitir/Smart View*). Encerre a transmissão preferencialmente pela fonte.

No modo dual, cada instância possui diretório e log próprios (`lazycast_instance_display1/`, `lazycast_instance_display2/`), porta RTP e tela distintas.

## Configuração

Arquivo `lazycast-config.conf` (gerado pelo instalador; reexecute `sudo ./install.sh` ou edite manualmente):

| Chave | Descrição | Padrão |
|---|---|---|
| `DISPLAY_MODE` | `1` single, `2` dual | — |
| `DISPLAYn_NAME` | Nome anunciado à fonte | `<hostname>-Displayn` |
| `DISPLAYn_IP`, `DISPLAYn_DHCP_START/END` | Rede P2P da instância (sub-redes diferentes) | `192.168.173.x` / `192.168.174.x` |
| `DISPLAYn_PLAYER_SELECT` | Sempre `0` (VLC); outros valores são ignorados | `0` |
| `DISPLAYn_SOUND_OUTPUT` | `0` HDMI, `1` P2 3,5 mm, `2` ALSA | `2` |
| `DISPLAYn_RTP_PORT` | Porta RTP de vídeo (distinta por display) | `1028` / `1030` |
| `DISPLAYn_SCREEN` | Índice da tela (0 = HDMI-1) | `0` / `1` |
| `DISABLE_1920_1080_60FPS` | Anuncia 1080p50 em vez de 1080p60 | `1` |
| `ENABLE_MOUSE_KEYBOARD` | Redireciona mouse/teclado (requer `python3-evdev`) | `0` |
| `LAZYCAST_AUTH` | `pbc` = sem PIN (botão WPS); `pin` = a fonte pede o PIN | `pbc` |
| `LAZYCAST_PIN` | PIN usado só com `LAZYCAST_AUTH=pin` | aleatório (gerado na instalação) |
| `MANAGE_FREQUENCY` | Alinha o canal do P2P ao da WLAN | `0` |

## Serviço systemd

```bash
sudo ./install-service.sh                 # instala e inicia
sudo systemctl status lazycast
sudo systemctl restart lazycast
sudo systemctl disable lazycast
journalctl -u lazycast -f                 # logs do serviço
./lazycast-status.sh                      # resumo do estado
```

O serviço roda como o usuário que executou o `sudo`, exporta o ambiente da sessão gráfica (Wayland/D-Bus) e envia notificações de desktop quando disponíveis.

## Estrutura do repositório

```
.
├── install.sh / install-service.sh / setup-hdmi.sh   instalação e configuração
├── all.sh / all-dual.sh                              orquestração P2P + DHCP + receptor
├── d2.py / d2-multi.py                               receptor RTSP/Miracast
├── lazycast-background.sh / lazycast.service         execução em background (systemd)
├── control/                                          UIBC (mouse/teclado) em C
├── tests/ test-*.sh                                  testes sem hardware
├── docs/                                             guias adicionais
└── mice.sh newmice.py project.py ...                 Miracast over Infrastructure e utilitários
```

## Testes

```bash
./test-syntax.sh                      # sintaxe de scripts e Python
./tests/test-static.sh                # regressões estáticas (Pi 5 / dual display)
./test-integration.sh everything      # fonte Miracast simulada (Linux)
```

Consulte [docs/TESTING-GUIDE.md](docs/TESTING-GUIDE.md) para o roteiro em hardware real.

## Solução de problemas

| Sintoma | Causa provável / ação |
|---|---|
| `Permission denied` no `journalctl` do serviço | Rode `sudo ./install-service.sh` novamente (ajusta dono dos arquivos) |
| Fonte pede PIN e não conecta | Confirme `LAZYCAST_AUTH=pbc` (sem PIN) ou, com `pin`, use o `LAZYCAST_PIN` do `lazycast-config.conf` |
| Display não aparece na fonte | `sudo wpa_cli interface` sem `p2p-dev-*`; desative o controle do NetworkManager sobre o Wi-Fi |
| Vídeo travado em 1080p60 | Defina `DISABLE_1920_1080_60FPS=1` |
| Display 2 não inicia | Falta segundo adaptador Wi-Fi P2P (veja o log em `lazycast_instance_display2/`) |
| Sem vídeo após `setup-hdmi.sh` antigo | Rode a versão atual: ela remove `vc4-fkms-v3d`; reinicie |
| Wi-Fi varrendo redes durante o cast | Desative varreduras em segundo plano; veja [docs/TIPS.md](docs/TIPS.md) |

## Limitações conhecidas

- HDCP não é suportado. Transmissão RTP não confiável pode causar artefatos em Wi-Fi congestionado.
- Backchannel de mouse/teclado depende da fonte.
- O Pi 5 não possui decodificador H.264 por hardware; a decodificação é por software (VLC).
- A seleção da tela de saída por instância no VLC depende do compositor; valide em hardware real.

## Documentação adicional

- [Guia de Dual Display](docs/DUAL-DISPLAY-GUIDE.md)
- [Guia de testes](docs/TESTING-GUIDE.md)
- [Miracast over Infrastructure (MICE)](docs/MICE.md)
- [Dicas](docs/TIPS.md)
- [Changelog](CHANGELOG.md)

## Licença

GNU GPL v3.0 — veja [LICENSE](LICENSE). Partes do player1 derivam de [Apress/raspberry-pi-gpu-audio-video-prog](https://github.com/Apress/raspberry-pi-gpu-audio-video-prog). O uso comercial de partes deste código é proibido pelos autores originais.
