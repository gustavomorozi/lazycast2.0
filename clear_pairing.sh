#!/bin/bash
#################################################################################
# Script de Limpeza de Informações de Pareamento
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "Limpando informações de pareamento antigas..."
sudo wpa_cli -i p2p-dev-wlan0 remove_network all 2>/dev/null || true
sudo wpa_cli -i p2p-dev-wlan0 save_config 2>/dev/null || true
echo "✓ Informações de pareamento limpas"