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

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Por favor, execute como root (sudo)"
    exit 1
fi

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
    echo "⚠ Raspberry Pi não-Pi5 detectado - Suporte dual HDMI pode ser limitado"
    PI5_DETECTED=false
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
    read -p "Escolha (1 ou 2): " display_choice
else
    echo "Nota: Para dual display, recomenda-se Raspberry Pi 5"
    read -p "Escolha (1 ou 2): " display_choice
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

if [ "$DISPLAY_MODE" = "1" ]; then
    read -p "Nome do display [$HOSTNAME]: " display1_name
    DISPLAY1_NAME=${display1_name:-$HOSTNAME}
    DISPLAY2_NAME=""
else
    read -p "Nome do Display 1 [${HOSTNAME}-Display1]: " display1_name
    DISPLAY1_NAME=${display1_name:-${HOSTNAME}-Display1}
    
    read -p "Nome do Display 2 [${HOSTNAME}-Display2]: " display2_name
    DISPLAY2_NAME=${display2_name:-${HOSTNAME}-Display2}
fi



echo ""
echo "=========================================="
echo "  Configuração de Player"
echo "=========================================="
echo ""
echo "Selecione o player:"
echo "1) player1 (menor latência, OpenMAX — Pi 1–4 32-bit)"
echo "2) player2 (imagens estáticas e som, OpenMAX — Pi 1–4 32-bit)"
echo "3) omxplayer (para Android, OpenMAX legado)"
echo "0) VLC/GStreamer (recomendado no Raspberry Pi 5 / 64-bit)"
echo ""

if [ "$PI5_DETECTED" = true ]; then
    echo "Raspberry Pi 5: OpenMAX/ilclient não são suportados neste hardware."
    echo "Use a opção 0 (VLC/GStreamer). As opções 1–3 falham na compilação ou em runtime."
    echo ""
    read -p "Escolha (0-3) [0]: " player_choice
    PLAYER_SELECT=${player_choice:-0}
    if [ "$PLAYER_SELECT" != "0" ]; then
        echo "⚠ Player $PLAYER_SELECT não é suportado no Raspberry Pi 5. Usando 0 (VLC/GStreamer)."
        PLAYER_SELECT=0
    fi
else
    read -p "Escolha (0-3) [2]: " player_choice
    PLAYER_SELECT=${player_choice:-2}
fi

echo ""
echo "=========================================="
echo "  Configuração de Áudio"
echo "=========================================="
echo ""
echo "Selecione a saída de áudio:"
echo "0) HDMI"
echo "1) 3.5mm audio jack"
echo "2) ALSA"
echo ""

read -p "Escolha (0-2) [2]: " audio_choice
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
read -p "Confirmar configuração? (S/n): " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Instalação cancelada."
    exit 0
fi

echo ""
echo "=========================================="
echo "  Aplicando Configuração"
echo "=========================================="
echo ""

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

# Configurações do Display 2 (HDMI-2)
DISPLAY2_NAME="$DISPLAY2_NAME"
DISPLAY2_IP="192.168.174.1"
DISPLAY2_DHCP_START="192.168.174.80"
DISPLAY2_DHCP_END="192.168.174.80"
DISPLAY2_SOUND_OUTPUT=$SOUND_OUTPUT
DISPLAY2_PLAYER_SELECT=$PLAYER_SELECT

# Configurações do Player
# 0: non-RPi systems (using vlc or gstreamer)
# 1: player1 has lower latency
# 2: player2 handles still images and sound better
# 3: omxplayer (para Android)
SOUND_OUTPUT_SELECT=$SOUND_OUTPUT
# 0: HDMI sound output
# 1: 3.5mm audio jack output
# 2: alsa

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

# Compilar o projeto
echo ""
echo "Compilando o projeto..."

# control (HID/teclado) é necessário em todos os modos
make -C control/.
CONTROL_OK=$?

OMX_OK=0
if [ "$PLAYER_SELECT" = "1" ] || [ "$PLAYER_SELECT" = "2" ] || [ "$PLAYER_SELECT" = "3" ]; then
    echo "Compilando backends OpenMAX (h264/player)..."
    make -C h264/. && make -C player/.
    OMX_OK=$?
else
    echo "Player VLC/GStreamer selecionado — pulando compilação OpenMAX (h264/player)."
fi

if [ "$CONTROL_OK" -eq 0 ] && [ "$OMX_OK" -eq 0 ]; then
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

# Tornar scripts executáveis
chmod +x all.sh all-dual.sh install.sh install-service.sh setup-hdmi.sh
chmod +x lazycast-background.sh lazycast-status.sh
chmod +x clear_pairing.sh player_health_check.sh check_dependencies.sh
chmod +x d2.py d2-multi.py project.py

echo ""
echo "=========================================="
echo "  Instalação Concluída!"
echo "=========================================="
echo ""
echo "Para iniciar o LazyCast:"
echo "  - Single Display: ./all.sh"
echo "  - Dual Display: ./all-dual.sh"
echo ""
echo "Para alterar a configuração posteriormente:"
echo "  - Edite o arquivo lazycast-config.conf"
echo "  - Execute ./install.sh novamente"
echo ""
read -p "Deseja instalar o serviço de inicialização automática no boot? (S/n): " install_service
if [[ ! "$install_service" =~ ^[Nn]$ ]]; then
    echo ""
    echo "Instalando serviço systemd..."
    ./install-service.sh
else
    echo ""
    echo "Serviço não instalado. Você pode instalar depois com:"
    echo "  sudo ./install-service.sh"
fi
echo ""