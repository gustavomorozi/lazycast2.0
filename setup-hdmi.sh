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
if [[ "$CPU_INFO" == *"BCM2712"* ]]; then
    echo "✓ Raspberry Pi 5 detectado"
    PI5=true
else
    echo "⚠ Raspberry Pi não-Pi5 detectado"
    PI5=false
fi

# Configurar framebuffers para dual display
if [ "$DISPLAY_MODE" = "2" ] && [ "$PI5" = true ]; then
    echo "Configurando para dual display (HDMI-1 e HDMI-2)..."
    
    # Verificar arquivo config.txt
    CONFIG_FILE="/boot/config.txt"
    
    # Backup do config.txt
    if [ ! -f "$CONFIG_FILE.backup" ]; then
        sudo cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
        echo "✓ Backup criado: $CONFIG_FILE.backup"
    fi
    
    # Adicionar configurações para dual display
    sudo sed -i '/^dtoverlay=vc4-fkms-v3d/a dtoverlay=vc4-fkms-v3d' "$CONFIG_FILE"
    
    # Configurar framebuffer para dual display
    if ! grep -q "dtoverlay=vc4-fkms-v3d" "$CONFIG_FILE"; then
        echo "dtoverlay=vc4-fkms-v3d" | sudo tee -a "$CONFIG_FILE"
    fi
    
    # Configurar resolução para ambos os displays
    if ! grep -q "hdmi_drive=1" "$CONFIG_FILE"; then
        echo "hdmi_drive=1" | sudo tee -a "$CONFIG_FILE"
    fi
    
    if ! grep -q "hdmi_group=1" "$CONFIG_FILE"; then
        echo "hdmi_group=1" | sudo tee -a "$CONFIG_FILE"
    fi
    
    if ! grep -q "hdmi_mode=16" "$CONFIG_FILE"; then
        echo "hdmi_mode=16" | sudo tee -a "$CONFIG_FILE"
    fi
    
    # Configurar segundo HDMI
    if ! grep -q "hdmi_drive=2" "$CONFIG_FILE"; then
        echo "hdmi_drive=2" | sudo tee -a "$CONFIG_FILE"
    fi
    
    if ! grep -q "hdmi_group=2" "$CONFIG_FILE"; then
        echo "hdmi_group=2" | sudo tee -a "$CONFIG_FILE"
    fi
    
    if ! grep -q "hdmi_mode=16" "$CONFIG_FILE"; then
        echo "hdmi_mode=16" | sudo tee -a "$CONFIG_FILE"
    fi
    
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