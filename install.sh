#!/bin/bash
#################################################################################
# Script de Instalação do LazyCast Dual Display
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#   You may copy, distribute and modify the software as long as you track
#   changes/dates in source files. Any modifications to our software
#   including (via compiler) GPL-licensed code must also be made available
#   under the GPL along with build & install instructions.
#
#################################################################################

echo "=========================================="
echo "  LazyCast Dual Display Installer"
echo "=========================================="
echo ""

# Opções: -y/--yes aceita todos os padrões (instalação sem perguntas); --no-service não instala o serviço
ASSUME_YES=0
DEFAULT_DISPLAY_MODE=1
FORCE=0
INSTALL_SERVICE=1
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --no-service) INSTALL_SERVICE=0 ;;
        --force) FORCE=1 ;;
        --dual) DEFAULT_DISPLAY_MODE=2 ;;
    esac
done

# Pergunta com valor padrão; com --yes (ou sem terminal interativo) usa o padrão
# uso: ask VARIAVEL "Pergunta" [padrão]
ask() {
    local __var="$1" __prompt="$2" __default="$3" __reply=""
    if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
        printf -v "$__var" '%s' "$__default"
        return
    fi
    read -r -p "$__prompt" __reply
    printf -v "$__var" '%s' "$__reply"
}

# Executa como root automaticamente (o usuário não precisa lembrar do sudo)
if [ "$EUID" -ne 0 ]; then
    echo "Elevando privilégios com sudo..."
    exec sudo -E bash "$0" "$@"
fi

# Entra no diretório do projeto e garante permissão de execução (perdida ao clonar/copiar)
cd "$(dirname "$0")" || exit 1
chmod +x ./*.sh ./*.py 2>/dev/null

# Dependências (Raspberry Pi OS Bookworm / Pi 5). Sem elas o make do control falha (libx11-dev)
# ou o receptor não sobe (busybox = udhcpd, vlc = player, wpa_cli = P2P).
missing_pkgs=()
command -v gcc >/dev/null 2>&1 || missing_pkgs+=(build-essential)
command -v make >/dev/null 2>&1 || missing_pkgs+=(make)
command -v wpa_cli >/dev/null 2>&1 || missing_pkgs+=(wpasupplicant)
command -v busybox >/dev/null 2>&1 || missing_pkgs+=(busybox)
command -v vlc >/dev/null 2>&1 || missing_pkgs+=(vlc)
command -v python3 >/dev/null 2>&1 || missing_pkgs+=(python3)
command -v iw >/dev/null 2>&1 || missing_pkgs+=(iw)
python3 -c "import gi; gi.require_version('Gtk', '3.0')" >/dev/null 2>&1 || missing_pkgs+=(python3-gi gir1.2-gtk-3.0)
command -v xrandr >/dev/null 2>&1 || missing_pkgs+=(x11-xserver-utils)
python3 -c "import evdev" >/dev/null 2>&1 || missing_pkgs+=(python3-evdev)
command -v notify-send >/dev/null 2>&1 || missing_pkgs+=(libnotify-bin)
dpkg -s libx11-dev >/dev/null 2>&1 || missing_pkgs+=(libx11-dev)
if [ ${#missing_pkgs[@]} -gt 0 ]; then
    echo "Pacotes ausentes: ${missing_pkgs[*]}"
    echo "Instalando automaticamente..."
    export DEBIAN_FRONTEND=noninteractive
    if ! { apt-get update && apt-get install -y "${missing_pkgs[@]}"; }; then
        echo "✗ Falha ao instalar dependências (${missing_pkgs[*]}). Verifique a conexão com a internet e tente novamente."
        exit 1
    fi
fi

# Adaptadores Wi-Fi e compatibilidade com Wi-Fi Direct (o interno e qualquer USB, em qualquer porta)
source ./lib-p2p.sh
print_wifi_adapters
P2P_ADAPTERS=$?
echo ""

# Detectar modelo do Raspberry Pi
echo "Detectando modelo do Raspberry Pi..."
CPU_INFO=$(grep Hardware /proc/cpuinfo)
PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
echo "Info do CPU: ${CPU_INFO:-n/a}"
echo "Modelo: ${PI_MODEL:-desconhecido}"

if [[ "$CPU_INFO" == *"BCM2712"* ]] || [[ "$PI_MODEL" == *"Raspberry Pi 5"* ]]; then
    echo "✓ Raspberry Pi 5 detectado - Suporte dual HDMI disponível"
    PI5_DETECTED=true
else
    PI5_DETECTED=false
    if [ "$FORCE" != "1" ]; then
        echo "✗ Esta versão suporta somente o Raspberry Pi 5. Use --force para instalar mesmo assim."
        exit 1
    fi
    echo "⚠ Hardware não-Pi5 (--force): sem suporte."
fi

echo ""
echo "=========================================="
echo "  Configuração de Display"
echo "=========================================="
echo ""
echo "Selecione o modo de display:"
echo "1) Single Display (Display único - HDMI-1)"
echo "2) Dual Display (Dois displays independentes - HDMI-1 e HDMI-2)"
echo ""

if [ "$PI5_DETECTED" = true ]; then
    ask display_choice "Escolha (1 ou 2): " "$DEFAULT_DISPLAY_MODE"
else
    echo "Nota: Para dual display, recomenda-se Raspberry Pi 5"
    ask display_choice "Escolha (1 ou 2): " "$DEFAULT_DISPLAY_MODE"
fi

case $display_choice in
    1)
        DISPLAY_MODE=1
        echo "✓ Modo Single Display selecionado"
        ;;
    2)
        DISPLAY_MODE=2
        echo "✓ Modo Dual Display selecionado"
        ;;
    *)
        echo "Opção inválida. Usando Single Display por padrão."
        DISPLAY_MODE=1
        ;;
esac

echo ""
echo "=========================================="
echo "  Configuração de Nomes dos Displays"
echo "=========================================="
echo ""

HOSTNAME=$(uname -n)
echo "Hostname atual: $HOSTNAME"
# Nome padrão do display: o já configurado (reinstalação) ou LazyCast-<animal> aleatório (instalação nova)
DEFAULT_NAME=""
if [ -f lazycast-config.conf ]; then
    DEFAULT_NAME=$(sed -n 's/^DISPLAY1_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' lazycast-config.conf | head -1)
fi
DEFAULT_NAME=${DEFAULT_NAME:-$(random_animal_name)}

if [ "$DISPLAY_MODE" = "1" ]; then
    ask display1_name "Nome do display [$DEFAULT_NAME]: " ""
    DISPLAY1_NAME=${display1_name:-$DEFAULT_NAME}
    DISPLAY2_NAME=""
else
    # Com um Wi-Fi só, o Windows/Android listam UM dispositivo (um nome); a 2ª fonte entra no mesmo
    # nome. Por isso o nome padrão é neutro, sem "-Display1" (que sugeria existir só a Tela 1).
    ask display1_name "Nome do display (aparece no Windows/celular) [$DEFAULT_NAME]: " ""
    DISPLAY1_NAME=${display1_name:-$DEFAULT_NAME}
    
    ask display2_name "Nome do Display 2 [${HOSTNAME}-Display2]: " ""
    DISPLAY2_NAME=${display2_name:-${DEFAULT_NAME}-2}
fi



echo ""
# Raspberry Pi 5: somente VLC (OpenMAX/ilclient não existem neste hardware)
PLAYER_SELECT=0

echo "=========================================="
echo "  Configuração de Áudio"
echo "=========================================="
echo ""
echo "Selecione a saída de áudio:"
echo "0) HDMI"
echo "1) 3.5mm audio jack"
echo "2) ALSA"
echo ""

ask audio_choice "Escolha (0-2) [2]: " ""
SOUND_OUTPUT=${audio_choice:-2}

echo ""
echo "=========================================="
echo "  Resumo da Configuração"
echo "=========================================="
echo ""
echo "Modo de Display: $([ "$DISPLAY_MODE" = "1" ] && echo "Single Display" || echo "Dual Display")"
echo "Nome Display 1: $DISPLAY1_NAME"
echo "Player: $PLAYER_SELECT"
echo "Áudio: $SOUND_OUTPUT"

if [ "$DISPLAY_MODE" = "2" ]; then
    echo "Nome Display 2: $DISPLAY2_NAME"
fi

echo ""
ask confirm "Confirmar configuração? (S/n): " "S"
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Instalação cancelada."
    exit 0
fi

echo ""
echo "=========================================="
echo "  Aplicando Configuração"
echo "=========================================="
echo ""

# PIN de conexão: reaproveita o existente (reinstalação) ou gera um aleatório com checksum WPS válido
source ./lib-p2p.sh
if [ -f lazycast-config.conf ]; then
    LAZYCAST_PIN=$(sed -n 's/^LAZYCAST_PIN="\{0,1\}\([0-9]\{8\}\)"\{0,1\}$/\1/p' lazycast-config.conf | head -1)
fi
LAZYCAST_PIN=${LAZYCAST_PIN:-$(gen_wps_pin)}
# Autenticação: pbc (padrão, sem PIN) ou pin; reinstalar preserva a escolha
if [ -f lazycast-config.conf ]; then
    LAZYCAST_AUTH=$(sed -n 's/^LAZYCAST_AUTH="\{0,1\}\(pbc\|pin\)"\{0,1\}$/\1/p' lazycast-config.conf | head -1)
fi
LAZYCAST_AUTH=${LAZYCAST_AUTH:-pbc}

# Criar arquivo de configuração
cat > lazycast-config.conf << EOF
# LazyCast Dual Display Configuration
# Configuração do LazyCast para Suporte a Múltiplas Telas

# Número de telas/displays suportados
# 1 = Single display (display único)
# 2 = Dual display (dois displays independentes)
DISPLAY_MODE=$DISPLAY_MODE

# Configurações do Display 1 (HDMI-1)
DISPLAY1_NAME="$DISPLAY1_NAME"
DISPLAY1_IP="192.168.173.1"
DISPLAY1_DHCP_START="192.168.173.80"
DISPLAY1_DHCP_END="192.168.173.80"
DISPLAY1_SOUND_OUTPUT=$SOUND_OUTPUT
DISPLAY1_PLAYER_SELECT=$PLAYER_SELECT
# Porta RTP e tela (0 = HDMI-1) desta instância; devem ser diferentes entre os displays
DISPLAY1_RTP_PORT=1028
DISPLAY1_SCREEN=0

# Configurações do Display 2 (HDMI-2)
DISPLAY2_NAME="$DISPLAY2_NAME"
DISPLAY2_IP="192.168.174.1"
DISPLAY2_DHCP_START="192.168.174.80"
DISPLAY2_DHCP_END="192.168.174.80"
DISPLAY2_SOUND_OUTPUT=$SOUND_OUTPUT
DISPLAY2_PLAYER_SELECT=$PLAYER_SELECT
DISPLAY2_RTP_PORT=1030
DISPLAY2_SCREEN=1

# Configurações do Player
# 0: VLC/GStreamer (único player suportado no Raspberry Pi 5)
SOUND_OUTPUT_SELECT=$SOUND_OUTPUT
# 0: HDMI sound output
# 1: 3.5mm audio jack output
# 2: alsa

# Autenticação ao conectar: "pbc" = sem PIN (botão WPS sempre ativo; qualquer aparelho ao alcance
# do Wi-Fi pode espelhar) ou "pin" = a fonte pede LAZYCAST_PIN.
LAZYCAST_AUTH="$LAZYCAST_AUTH"
LAZYCAST_PIN="$LAZYCAST_PIN"

# Dual display: "auto" usa 2 grupos se houver 2 adaptadores Wi-Fi Direct; senão 1 grupo com 2 fontes
# (modo compartilhado). "independent" exige 2 adaptadores.
DUAL_STRATEGY="auto"

# Configurações adicionais
DISABLE_1920_1080_60FPS=1
ENABLE_MOUSE_KEYBOARD=0
DISPLAY_POWER_MANAGEMENT=0

# Gerenciamento de frequência WiFi
MANAGE_FREQUENCY=0
EOF

echo "✓ Arquivo de configuração criado: lazycast-config.conf"

# O arquivo foi criado como root; devolver a posse ao usuário que chamou o sudo
if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" lazycast-config.conf
fi

if [ "$DISPLAY_MODE" = "2" ] && [ "$P2P_ADAPTERS" -lt 2 ]; then
    echo "ℹ Só há $P2P_ADAPTERS adaptador(es) Wi-Fi com Wi-Fi Direct (P2P-client + P2P-GO). O Wi-Fi interno do Pi 5 sustenta"
    echo "  um grupo por vez, então o dual display usará o modo GRUPO COMPARTILHADO (experimental): as duas fontes"
    echo "  entram no mesmo Wi-Fi do Pi (a 1ª conectada vai para o Display 1, a 2ª para o Display 2)."
    echo "  Para dois grupos independentes, plugue um adaptador USB compatível (qualquer porta):"
    echo "  iw phy | grep -A9 'Supported interface modes' deve listar P2P-client e P2P-GO."
fi

# Compilar o projeto
echo ""
echo "Compilando o projeto..."

# control (HID/teclado) é necessário em todos os modos
make -C control/.
CONTROL_OK=$?

if [ "$CONTROL_OK" -eq 0 ]; then
    echo "✓ Compilação concluída com sucesso"
else
    echo "✗ Erro na compilação"
    exit 1
fi

# Garantir que o usuário do serviço consiga gravar logs e configs
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" .
    touch lazycast-background.log
    chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" lazycast-background.log
    chmod 664 lazycast-background.log
fi

# Versão anterior criava este arquivo (unmanaged-devices), que não impedia o NetworkManager de
# derrubar o grupo P2P. O LazyCast agora pausa o NetworkManager enquanto roda (lib-p2p.sh).
if [ -f /etc/NetworkManager/conf.d/99-lazycast-p2p.conf ]; then
    rm -f /etc/NetworkManager/conf.d/99-lazycast-p2p.conf
    systemctl reload NetworkManager 2>/dev/null || true
fi

# Tornar scripts executáveis
chmod +x all.sh all-dual.sh install.sh install-service.sh setup-hdmi.sh
chmod +x lazycast-background.sh lazycast-status.sh
chmod +x clear_pairing.sh check_dependencies.sh lib-p2p.sh
chmod +x d2.py d2-multi.py project.py

# Painel gráfico: atalho no menu de aplicativos (gui/lazycast-gui.py)
if [ -d /usr/share/applications ]; then
    sed "s|@DIR@|$(pwd)|" gui/lazycast.desktop.in > /usr/share/applications/lazycast.desktop
    chmod 644 /usr/share/applications/lazycast.desktop
    chmod +x gui/lazycast-gui.py
    echo "✓ Painel gráfico instalado: menu de aplicativos > LazyCast"
fi

# Pi 5 + dual display: garante driver KMS/HDMI sem perguntar (reboot fica a cargo do usuário)
if [ "$PI5_DETECTED" = true ] && [ "$DISPLAY_MODE" = "2" ]; then
    LAZYCAST_NO_REBOOT_PROMPT=1 ./setup-hdmi.sh || echo "⚠ setup-hdmi.sh falhou; verifique manualmente."
fi

echo ""
echo "=========================================="
echo "  Instalação Concluída!"
echo "=========================================="
echo ""
if [ "$LAZYCAST_AUTH" = "pin" ]; then
    echo "PIN de conexão (digite na fonte, Windows/Android): $LAZYCAST_PIN"
else
    echo "Conexão SEM PIN (botão WPS): qualquer aparelho ao alcance pode espelhar. Para exigir PIN: LAZYCAST_AUTH=pin em lazycast-config.conf."
fi
echo ""
echo "Para iniciar o LazyCast:"
echo "  - Single Display: ./all.sh"
echo "  - Dual Display: ./all-dual.sh"
echo ""
echo "Para alterar a configuração posteriormente:"
echo "  - Edite o arquivo lazycast-config.conf"
echo "  - Execute ./install.sh novamente"
echo ""
if [ "$INSTALL_SERVICE" = "1" ]; then
    echo ""
    echo "Instalando serviço systemd..."
    ./install-service.sh
else
    echo ""
    echo "Serviço não instalado (--no-service). Você pode instalar depois com:"
    echo "  sudo ./install-service.sh"
fi
echo ""