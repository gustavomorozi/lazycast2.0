#!/bin/bash
#################################################################################
# Script para tornar scripts executáveis
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "Tornando scripts executáveis..."

chmod +x all.sh
chmod +x all-dual.sh
chmod +x install.sh
chmod +x setup-hdmi.sh
chmod +x d2.py
chmod +x d2-multi.py
chmod +x project.py
chmod +x mice.sh
chmod +x vlcbased.sh
chmod +x win10debug.sh
chmod +x removep2p.sh
chmod +x resetwpa.sh
chmod +x logging.sh
chmod +x mice.sh
chmod +x wiresharkscript.sh

echo "✓ Scripts tornados executáveis"
echo ""
echo "Scripts principais:"
echo "  - ./install.sh          : Instalação e configuração"
echo "  - ./setup-hdmi.sh       : Configuração HDMI (requer root)"
echo "  - ./all.sh              : Single display mode"
echo "  - ./all-dual.sh         : Dual display mode"