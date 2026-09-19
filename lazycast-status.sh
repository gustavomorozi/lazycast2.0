#!/bin/bash
#################################################################################
# Script de Status do LazyCast
# Mostra o status atual do LazyCast com notificações visuais
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

LAZYCAST_DIR="/home/pi/lazycast2.0"
cd "$LAZYCAST_DIR" 2>/dev/null || cd "$(dirname "$0")"

# Carregar configurações
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
else
    DISPLAY_MODE=1
    DISPLAY1_NAME="LazyCast"
fi

# Função para mostrar notificação
show_notification() {
    local title="$1"
    local message="$2"
    local urgency="$3"  # low, normal, critical
    
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$message" --urgency="$urgency" --icon="display" 2>/dev/null
    fi
}

# Verificar se o serviço systemd está rodando
if systemctl is-active --quiet lazycast.service 2>/dev/null; then
    SERVICE_STATUS="✓ Ativo (systemd)"
    SERVICE_COLOR="#00FF00"
else
    SERVICE_STATUS="✗ Inativo (systemd)"
    SERVICE_COLOR="#FF0000"
fi

# Verificar se os processos estão rodando
if pgrep -f "all.sh" > /dev/null || pgrep -f "all-dual.sh" > /dev/null; then
    PROCESS_STATUS="✓ Rodando"
    PROCESS_COLOR="#00FF00"
else
    PROCESS_STATUS="✗ Parado"
    PROCESS_COLOR="#FF0000"
fi

# Verificar status dos displays
DISPLAY1_STATUS="Desconhecido"
DISPLAY2_STATUS="N/A"

if [ "$DISPLAY_MODE" = "2" ]; then
    if [ -f "lazycast_instance_display1/lazycast_display1.log" ]; then
        if grep -q "The display is ready" lazycast_instance_display1/lazycast_display1.log; then
            DISPLAY1_STATUS="✓ Pronto ($DISPLAY1_NAME)"
        else
            DISPLAY1_STATUS="⏳ Iniciando ($DISPLAY1_NAME)"
        fi
    else
        DISPLAY1_STATUS="✗ Não iniciado ($DISPLAY1_NAME)"
    fi
    
    if [ -f "lazycast_instance_display2/lazycast_display2.log" ]; then
        if grep -q "The display is ready" lazycast_instance_display2/lazycast_display2.log; then
            DISPLAY2_STATUS="✓ Pronto ($DISPLAY2_NAME)"
        else
            DISPLAY2_STATUS="⏳ Iniciando ($DISPLAY2_NAME)"
        fi
    else
        DISPLAY2_STATUS="✗ Não iniciado ($DISPLAY2_NAME)"
    fi
else
    if [ -f "lazycast-background.log" ]; then
        if grep -q "The display is ready" lazycast-background.log; then
            DISPLAY1_STATUS="✓ Pronto ($DISPLAY1_NAME)"
        else
            DISPLAY1_STATUS="⏳ Iniciando ($DISPLAY1_NAME)"
        fi
    else
        DISPLAY1_STATUS="✗ Não iniciado ($DISPLAY1_NAME)"
    fi
fi

# Criar mensagem de status
STATUS_MESSAGE="LazyCast Status
================

Serviço: $SERVICE_STATUS
Processos: $PROCESS_STATUS

Modo: $([ "$DISPLAY_MODE" = "2" ] && echo "Dual Display" || echo "Single Display")

Display 1: $DISPLAY1_STATUS"

if [ "$DISPLAY_MODE" = "2" ]; then
    STATUS_MESSAGE="$STATUS_MESSAGE
Display 2: $DISPLAY2_STATUS"
fi

# Mostrar status no terminal
echo "$STATUS_MESSAGE"

# Tentar mostrar notificação gráfica
if [ "$PROCESS_STATUS" = "✓ Rodando" ]; then
    if [ "$DISPLAY_MODE" = "2" ]; then
        if [[ "$DISPLAY1_STATUS" == *"✓ Pronto"* ]] && [[ "$DISPLAY2_STATUS" == *"✓ Pronto"* ]]; then
            show_notification "LazyCast" "Todos os displays estão prontos e aguardando conexão" "normal"
        else
            show_notification "LazyCast" "Displays estão iniciando..." "low"
        fi
    else
        if [[ "$DISPLAY1_STATUS" == *"✓ Pronto"* ]]; then
            show_notification "LazyCast" "Display está pronto e aguardando conexão" "normal"
        else
            show_notification "LazyCast" "Display está iniciando..." "low"
        fi
    fi
else
    show_notification "LazyCast" "Serviço não está rodando" "critical"
fi

# Opção para usar interface gráfica se disponível
if command -v zenity &> /dev/null; then
    zenity --info --title="LazyCast Status" --text="$STATUS_MESSAGE" --width=400 2>/dev/null
fi