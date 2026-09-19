#!/bin/bash
#################################################################################
# Script de Verificação de Saúde do Player
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

check_player_health() {
    local player_pid=$1
    local player_name=$2
    
    if [ -z "$player_pid" ]; then
        return 1
    fi
    
    # Verificar uso de memória
    local mem_usage=$(ps -p $player_pid -o rss= 2>/dev/null || echo "0")
    local mem_mb=$((mem_usage / 1024))
    
    if [ $mem_mb -gt 500 ]; then
        echo "ALERTA: $player_name usando muita memória (${mem_mb}MB)"
        kill -9 $player_pid 2>/dev/null
        return 1
    fi
    
    return 0
}

echo "Verificando saúde dos players..."

# Verificar players ativos
for pid in $(pgrep -f "h264.bin"); do
    check_player_health $pid "h264.bin"
done

for pid in $(pgrep -f "player.bin"); do
    check_player_health $pid "player.bin"
done

echo "✓ Verificação concluída"