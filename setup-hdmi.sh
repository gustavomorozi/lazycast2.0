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
# [RPi5] O Raspberry Pi 5 só funciona com o driver KMS (vc4-kms-v3d) e já traz duas
# saídas HDMI independentes. As versões anteriores deste script adicionavam
# 'dtoverlay=vc4-fkms-v3d' (não suportado no Pi 5 — pode deixar o sistema sem vídeo) e
# opções legadas hdmi_group/hdmi_mode (ignoradas pelo KMS). Agora o script apenas
# garante o overlay correto (revertendo o que a versão antiga tenha gravado) e mostra
# o estado dos conectores HDMI.
#################################################################################

# Carregar configurações
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
else
    echo "Arquivo de configuração não encontrado."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute como root (sudo)"
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

CHANGED=0

if [ "$PI5" = true ]; then
    # Bookworm usa /boot/firmware/config.txt
    if [ -f /boot/firmware/config.txt ]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    else
        CONFIG_FILE="/boot/config.txt"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "✗ Arquivo $CONFIG_FILE não encontrado"
        exit 1
    fi

    # Backup do config.txt (apenas na primeira execução)
    if [ ! -f "$CONFIG_FILE.backup" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
        echo "✓ Backup criado: $CONFIG_FILE.backup"
    fi

    # Reverter o que a versão antiga do script gravou: fkms não existe no Pi 5
    if grep -q "^dtoverlay=vc4-fkms-v3d" "$CONFIG_FILE"; then
        sed -i 's|^dtoverlay=vc4-fkms-v3d|#&  # desativado por setup-hdmi.sh (nao suportado no Pi 5)|' "$CONFIG_FILE"
        echo "✓ dtoverlay=vc4-fkms-v3d desativado (não suportado no Raspberry Pi 5)"
        CHANGED=1
    fi

    # Garantir o driver KMS
    if ! grep -q "^dtoverlay=vc4-kms-v3d" "$CONFIG_FILE"; then
        echo "dtoverlay=vc4-kms-v3d" >> "$CONFIG_FILE"
        echo "✓ dtoverlay=vc4-kms-v3d adicionado"
        CHANGED=1
    fi

    # hdmi_group/hdmi_mode/hdmi_drive são opções do firmware antigo e são ignoradas pelo KMS.
    # Removemos apenas as linhas exatas que a versão antiga do script adicionou.
    for line in "hdmi_drive:0=2" "hdmi_group:0=1" "hdmi_mode:0=16" "hdmi_drive:1=2" "hdmi_group:1=1" "hdmi_mode:1=16"; do
        if grep -qxF "$line" "$CONFIG_FILE"; then
            grep -vxF "$line" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && cat "$CONFIG_FILE.tmp" > "$CONFIG_FILE"
            rm -f "$CONFIG_FILE.tmp"
            echo "✓ Linha legada removida: $line"
            CHANGED=1
        fi
    done

    echo ""
    echo "Estado dos conectores HDMI (KMS):"
    found=0
    for c in /sys/class/drm/card*-HDMI-A-*; do
        [ -e "$c/status" ] || continue
        found=1
        echo "  $(basename "$c"): $(cat "$c/status")"
    done
    [ "$found" = "0" ] && echo "  (nenhum conector HDMI encontrado em /sys/class/drm)"

    if [ "$DISPLAY_MODE" = "2" ]; then
        echo ""
        echo "Dual display: conecte um monitor em cada HDMI. A resolução/posição de cada saída"
        echo "é ajustada no desktop (Configurações de tela / wlr-randr); o LazyCast usa a tela"
        echo "DISPLAY1_SCREEN/DISPLAY2_SCREEN do lazycast-config.conf para cada instância."
    fi
else
    echo "Configuração single display / hardware não-Pi5: nada a alterar."
fi

echo ""
echo "=========================================="
echo "  Configuração HDMI Concluída"
echo "=========================================="
echo ""

if [ "$CHANGED" = "1" ]; then
    echo "⚠ Reboot necessário para aplicar as mudanças"
    read -p "Deseja reiniciar agora? (S/n): " reboot_choice
    if [[ ! "$reboot_choice" =~ ^[Nn]$ ]]; then
        reboot
    fi
else
    echo "Nenhuma alteração no config.txt foi necessária (sem reboot)."
fi
