#!/bin/bash
#################################################################################
# Script de Background do LazyCast
# Inicia o LazyCast em background com notificações na interface gráfica
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

# Caminho do diretório do LazyCast
LAZYCAST_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$LAZYCAST_DIR" || exit 1

if [ -d /var/log/lazycast ] && [ -w /var/log/lazycast ]; then
    LOG_FILE="/var/log/lazycast/lazycast-background.log"
elif [ -w "$LAZYCAST_DIR" ] && { [ ! -e "$LAZYCAST_DIR/lazycast-background.log" ] || [ -w "$LAZYCAST_DIR/lazycast-background.log" ]; }; then
    LOG_FILE="$LAZYCAST_DIR/lazycast-background.log"
else
    LOG_FILE="/tmp/lazycast-background.log"
fi

append_log() {
    echo "$@" >> "$LOG_FILE" 2>/dev/null || echo "$@" >> /tmp/lazycast-background.log
}

# Carregar configurações
if [ -f lazycast-config.conf ]; then
    source lazycast-config.conf
else
    DISPLAY_MODE=1
    DISPLAY1_NAME="LazyCast"
fi

# Função para enviar notificação
send_notification() {
    local title="$1"
    local message="$2"
    local icon="$3"
    
    # Tenta diferentes métodos de notificação
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$message" --icon="$icon" 2>/dev/null
    elif command -v zenity &> /dev/null; then
        zenity --notification --text="$title: $message" 2>/dev/null
    fi
    
    # Log da notificação
    append_log "[$(date '+%Y-%m-%d %H:%M:%S')] NOTIFICAÇÃO: $title - $message"
}

# Função para iniciar LazyCast
start_lazycast() {
    local mode=$1
    
    send_notification "LazyCast" "Iniciando serviço de display wireless..." "display"
    
    if [ "$mode" = "2" ]; then
        # Modo Dual Display
        send_notification "LazyCast Dual Display" "Iniciando dois displays independentes..." "video-display"
        ./all-dual.sh >> "$LOG_FILE" 2>&1
    else
        # Modo Single Display
        send_notification "LazyCast" "Iniciando receptor wireless..." "display"
        ./all.sh >> "$LOG_FILE" 2>&1
    fi
}

# Função para monitorar status
monitor_status() {
    local mode=$1
    
    while true; do
        sleep 30
        
        # Verificar se o LazyCast está rodando
        if pgrep -f "all.sh" > /dev/null || pgrep -f "all-dual.sh" > /dev/null; then
            # LazyCast está rodando
            if [ "$mode" = "2" ]; then
                if [ -f "lazycast_instance_display1/lazycast_display1.log" ] && \
                   [ -f "lazycast_instance_display2/lazycast_display2.log" ]; then
                    # Verificar se ambos os displays estão ativos
                    if grep -q "The display is ready" lazycast_instance_display1/lazycast_display1.log && \
                       grep -q "The display is ready" lazycast_instance_display2/lazycast_display2.log; then
                        send_notification "LazyCast" "Ambos os displays estão prontos e aguardando conexão" "video-display"
                    fi
                fi
            else
                if [ -f "$LOG_FILE" ] && grep -q "The display is ready" "$LOG_FILE"; then
                    send_notification "LazyCast" "Display pronto e aguardando conexão" "display"
                fi
            fi
        else
            # LazyCast não está rodando, tentar reiniciar
            send_notification "LazyCast" "Serviço parado, reiniciando..." "dialog-warning"
            start_lazycast "$mode"
        fi
    done
}

# Notificação de início
send_notification "LazyCast" "Serviço de display wireless iniciado" "display"

if [ "$DISPLAY_MODE" = "2" ]; then
    send_notification "LazyCast Dual Display" "Modo dual display ativado" "video-display"
    send_notification "LazyCast" "Display 1: $DISPLAY1_NAME" "display"
    send_notification "LazyCast" "Display 2: $DISPLAY2_NAME" "display"
    
    # Iniciar em background
    start_lazycast "2" &
    
    # Iniciar monitoramento
    monitor_status "2" &
else
    send_notification "LazyCast" "Modo single display ativado" "display"
    send_notification "LazyCast" "Display: $DISPLAY1_NAME" "display"
    
    # Iniciar em background
    start_lazycast "1" &
    
    # Iniciar monitoramento
    monitor_status "1" &
fi

# Manter o script rodando
wait