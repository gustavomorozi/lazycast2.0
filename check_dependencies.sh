#!/bin/bash
#################################################################################
# Script de Verificação de Dependências
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "Verificando dependências..."

missing_deps=()

# Verificar Python 3
if ! command -v python3 &> /dev/null; then
    missing_deps+=("python3")
fi

# Verificar evdev
if ! python3 -c "import evdev" 2>/dev/null; then
    echo "⚠ evdev não instalado (opcional para mouse/teclado)"
fi

# Verificar VLC (opcional)
if ! command -v vlc &> /dev/null; then
    echo "⚠ VLC não instalado (opcional)"
fi

# Verificar wpa_cli
if ! command -v wpa_cli &> /dev/null; then
    missing_deps+=("wpa_cli")
fi

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "❌ Dependências faltando: ${missing_deps[*]}"
    echo "Instale com: sudo apt install ${missing_deps[*]}"
    exit 1
else
    echo "✓ Todas as dependências estão instaladas"
fi