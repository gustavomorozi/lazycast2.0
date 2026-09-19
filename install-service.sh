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

# Caminho do diretório do LazyCast (diretório onde este script está)
LAZYCAST_DIR="$(cd "$(dirname "$0")" && pwd)"
# Usuário que executará o serviço (quem chamou o sudo)
LAZYCAST_USER="${SUDO_USER:-pi}"

# Verificar se o diretório existe
if [ ! -d "$LAZYCAST_DIR" ]; then
    echo "Diretório do LazyCast não encontrado: $LAZYCAST_DIR"
    echo "Por favor, ajuste o caminho no script ou instale o LazyCast primeiro."
    exit 1
fi

# Copiar arquivo de serviço
echo "Copiando arquivo de serviço systemd..."
cp "$LAZYCAST_DIR/lazycast.service" /etc/systemd/system/

# Ajustar caminho e usuário no arquivo de serviço
sed -i "s|/home/pi/lazycast2.0|$LAZYCAST_DIR|g" /etc/systemd/system/lazycast.service
sed -i "s|^User=.*|User=$LAZYCAST_USER|" /etc/systemd/system/lazycast.service
# UID real do usuário no runtime dir / barramento D-Bus da sessão
LAZYCAST_UID="$(id -u "$LAZYCAST_USER" 2>/dev/null || echo 1000)"
sed -i "s|/run/user/[0-9]*|/run/user/$LAZYCAST_UID|g" /etc/systemd/system/lazycast.service
echo "Diretório: $LAZYCAST_DIR"
echo "Usuário: $LAZYCAST_USER"

# O serviço roda como usuário comum; o clone/install como root deixa arquivos sem permissão de escrita
if id "$LAZYCAST_USER" >/dev/null 2>&1; then
    chown -R "$LAZYCAST_USER":"$(id -gn "$LAZYCAST_USER")" "$LAZYCAST_DIR"
    touch "$LAZYCAST_DIR/lazycast-background.log"
    chown "$LAZYCAST_USER":"$(id -gn "$LAZYCAST_USER")" "$LAZYCAST_DIR/lazycast-background.log"
    chmod 664 "$LAZYCAST_DIR/lazycast-background.log"
fi

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
echo "Iniciando (ou reiniciando) serviço LazyCast..."
# restart: se já estava ativo (reinstalação), "start" não recarregaria o código novo
systemctl restart lazycast.service

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
echo "  cat $LAZYCAST_DIR/lazycast-background.log - Ver logs no diretório do projeto"
echo "  cat /var/log/lazycast/lazycast-background.log - Ver logs do serviço"
echo ""