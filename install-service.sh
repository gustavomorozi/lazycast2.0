#!/bin/bash
#################################################################################
# Script de Instalação do Serviço Systemd do LazyCast
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "=========================================="
echo "  Instalação do Serviço LazyCast"
echo "=========================================="
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Por favor, execute como root (sudo)"
    exit 1
fi

# Caminho do diretório do LazyCast
LAZYCAST_DIR="/home/pi/lazycast2.0"

# Verificar se o diretório existe
if [ ! -d "$LAZYCAST_DIR" ]; then
    echo "Diretório do LazyCast não encontrado: $LAZYCAST_DIR"
    echo "Por favor, ajuste o caminho no script ou instale o LazyCast primeiro."
    exit 1
fi

# Copiar arquivo de serviço
echo "Copiando arquivo de serviço systemd..."
cp "$LAZYCAST_DIR/lazycast.service" /etc/systemd/system/

# Ajustar caminho no arquivo de serviço se necessário
sed -i "s|/home/pi/lazycast2.0|$LAZYCAST_DIR|g" /etc/systemd/system/lazycast.service

# Tornar scripts executáveis
echo "Tornando scripts executáveis..."
chmod +x "$LAZYCAST_DIR/lazycast-background.sh"
chmod +x "$LAZYCAST_DIR/all.sh"
chmod +x "$LAZYCAST_DIR/all-dual.sh"
chmod +x "$LAZYCAST_DIR/lazycast-status.sh"

# Recarregar systemd
echo "Recarregando systemd..."
systemctl daemon-reload

# Habilitar serviço
echo "Habilitando serviço LazyCast..."
systemctl enable lazycast.service

# Iniciar serviço
echo "Iniciando serviço LazyCast..."
systemctl start lazycast.service

# Verificar status
sleep 2
echo ""
echo "Status do serviço:"
systemctl status lazycast.service --no-pager

echo ""
echo "=========================================="
echo "  Instalação Concluída!"
echo "=========================================="
echo ""
echo "O LazyCast agora iniciará automaticamente no boot."
echo "Ele rodará em background com notificações na interface gráfica."
echo ""
echo "Comandos úteis:"
echo "  sudo systemctl status lazycast  - Ver status do serviço"
echo "  sudo systemctl stop lazycast    - Parar o serviço"
echo "  sudo systemctl start lazycast   - Iniciar o serviço"
echo "  sudo systemctl restart lazycast - Reiniciar o serviço"
echo "  sudo systemctl disable lazycast - Desabilitar início automático"
echo ""
echo "Logs:"
echo "  journalctl -u lazycast -f       - Ver logs do serviço"
echo "  cat $LAZYCAST_DIR/lazycast-background.log - Ver logs específicos"
echo ""