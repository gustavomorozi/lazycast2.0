#!/bin/bash
#################################################################################
# Script de Configuração HDMI para Raspberry Pi 5
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#   You may copy, distribute and modify the software as long as you track
#   changes/dates in source files. Any modifications to our software
#   including (via compiler) GPL-licensed code must also be made available
#   under the GPL along with build & install instructions.
#
#################################################################################

# Carregar configurações
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
else
    echo "Arquivo de configuração não encontrado."
    exit 1
fi

echo "=========================================="
echo "  Configuração HDMI - Raspberry Pi 5"
echo "=========================================="
echo ""

# Detectar modelo do Raspberry Pi
CPU_INFO=$(grep Hardware /proc/cpuinfo)
PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
if [[ "$CPU_INFO" == *"BCM2712"* ]] || [[ "$PI_MODEL" == *"Raspberry Pi 5"* ]]; then
    echo "✓ Raspberry Pi 5 detectado"
    PI5=true
else
    echo "⚠ Raspberry Pi não-Pi5 detectado"
    PI5=false
fi

# Configurar framebuffers para dual display
if [ "$DISPLAY_MODE" = "2" ] && [ "$PI5" = true ]; then
    echo "Configurando para dual display (HDMI-1 e HDMI-2)..."
    
    # Verificar arquivo config.txt (Bookworm usa /boot/firmware/config.txt)
    if [ -f /boot/firmware/config.txt ]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    else
        CONFIG_FILE="/boot/config.txt"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "✗ Arquivo $CONFIG_FILE não encontrado"
        exit 1
    fi
    
    # Backup do config.txt
    if [ ! -f "$CONFIG_FILE.backup" ]; then
        sudo cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
        echo "✓ Backup criado: $CONFIG_FILE.backup"
    fi
    
    # Adiciona uma linha ao config.txt apenas se ainda não existir
    add_config_line() {
        local line="$1"
        if ! grep -qxF "$line" "$CONFIG_FILE"; then
            echo "$line" | sudo tee -a "$CONFIG_FILE" > /dev/null
            echo "  + $line"
        fi
    }

    # Driver de vídeo
    if ! grep -q "^dtoverlay=vc4-.*kms-v3d" "$CONFIG_FILE"; then
        add_config_line "dtoverlay=vc4-fkms-v3d"
    fi

    # HDMI-1 (índice 0) e HDMI-2 (índice 1): 1080p60, modo HDMI (com áudio)
    add_config_line "hdmi_drive:0=2"
    add_config_line "hdmi_group:0=1"
    add_config_line "hdmi_mode:0=16"
    add_config_line "hdmi_drive:1=2"
    add_config_line "hdmi_group:1=1"
    add_config_line "hdmi_mode:1=16"
    
    echo "✓ Configurações HDMI adicionadas ao config.txt"
    echo "⚠ Reboot necessário para aplicar as mudanças"
    
else
    echo "Configuração single display"
    echo "Usando configurações padrão do sistema"
fi

echo ""
echo "=========================================="
echo "  Configuração HDMI Concluída"
echo "=========================================="
echo ""

if [ "$DISPLAY_MODE" = "2" ] && [ "$PI5" = true ]; then
    read -p "Deseja reiniciar agora? (S/n): " reboot_choice
    if [[ ! "$reboot_choice" =~ ^[Nn]$ ]]; then
        sudo reboot
    fi
fi