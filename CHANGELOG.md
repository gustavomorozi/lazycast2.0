# Changelog - LazyCast Dual Display

## [Versão 2.3] - Inicialização Automática e Notificações

### Adicionado
- **Serviço Systemd**: Implementado serviço systemd para inicialização automática no boot
- **Script de Background**: `lazycast-background.sh` para execução em background com monitoramento
- **Script de Instalação de Serviço**: `install-service.sh` para configuração automática do systemd
- **Script de Status**: `lazycast-status.sh` para verificação do status com notificações visuais
- **Sistema de Notificações**: Notificações na interface gráfica sobre status do LazyCast
- **Monitoramento Automático**: Sistema monitora e reinicia o LazyCast se necessário
- **Integração com Instalador**: Instalador agora oferece opção de instalação do serviço

### Funcionalidades do Sistema de Serviço
- **Inicialização Automática**: LazyCast inicia automaticamente no boot
- **Execução em Background**: Roda sem interferir com o uso normal do sistema
- **Notificações Gráficas**: Status mostrado através de notificações do sistema
- **Monitoramento de Saúde**: Sistema detecta problemas e reinicia automaticamente
- **Status Detalhado**: Script dedicado para verificar status atual
- **Log Centralizado**: Logs específicos para operação em background

### Comandos de Gerenciamento
- `sudo systemctl status lazycast` - Ver status do serviço
- `sudo systemctl stop lazycast` - Parar o serviço
- `sudo systemctl start lazycast` - Iniciar o serviço
- `sudo systemctl restart lazycast` - Reiniciar o serviço
- `sudo systemctl disable lazycast` - Desabilitar início automático
- `./lazycast-status.sh` - Ver status detalhado com notificações

### Benefícios
- **Conveniência**: Não precisa iniciar manualmente após cada boot
- **Invisibilidade**: Roda em background sem janelas de terminal
- **Informação**: Usuário sempre sabe o status através de notificações
- **Confiabilidade**: Sistema automático recupera de falhas
- **Profissional**: Funciona como um serviço de sistema adequado

### Arquivos Novos
- `lazycast.service` - Arquivo de configuração systemd
- `lazycast-background.sh` - Script de execução em background
- `install-service.sh` - Script de instalação do serviço
- `lazycast-status.sh` - Script de verificação de status

### Arquivos Modificados
- `install.sh` - Adicionada opção de instalação do serviço
- `README.md` - Adicionada seção sobre inicialização automática

### Notas
- Requer bibliotecas de notificação (notify-send, zenity)
- Funciona tanto em modo single quanto dual display
- Logs são salvos em `lazycast-background.log`
- Serviço pode ser desabilitado se não for desejado

## [Versão 2.2] - Remoção de PIN

### Removido
- **Sistema de PIN**: Removida a necessidade de PIN para conexão
- **Prompt de PIN**: Eliminada a solicitação de PIN durante conexão
- **Configuração de PIN**: Removida configuração de PIN do instalador e arquivos de configuração
- **Variáveis de PIN**: Removidas variáveis DISPLAY1_PIN e DISPLAY2_PIN

### Benefícios
- **Conexão Simplificada**: Processo de conexão mais rápido e direto
- **Experiência do Usuário**: Menos etapas para conectar dispositivos
- **Compatibilidade**: Melhor compatibilidade com diferentes dispositivos de origem

### Arquivos Modificados
- `all.sh`: Removida lógica de PIN
- `all-dual.sh`: Removida lógica de PIN em instâncias dual display
- `install.sh`: Removida configuração de PIN do instalador
- `README.md`: Atualizada documentação removendo referências a PIN
- `DUAL-DISPLAY-GUIDE.md`: Atualizado guia removendo PIN

### Notas
- A remoção do PIN simplifica o processo de conexão
- Segurança depende da rede WiFi local (como na configuração original)
- Recomenda-se usar em redes confiáveis

## [Versão 2.1] - Dual Display Support

### Adicionado
- **Suporte Dual Display para Raspberry Pi 5**: Sistema completo para operar dois receptores Miracast independentes, um para cada saída HDMI
- **Instalador Interativo (`install.sh`)**: Script de instalação com interface amigável para configuração
- **Configuração HDMI (`setup-hdmi.sh`)**: Script automático para configurar saídas HDMI no Raspberry Pi 5
- **Arquivo de Configuração (`lazycast-config.conf`)**: Sistema centralizado de configuração para todas as opções
- **Script Dual Display (`all-dual.sh`)**: Script principal para operação em modo dual display
- **Receiver Multi-Display (`d2-multi.py`)**: Versão modificada do d2.py com suporte a múltiplas instâncias
- **Guia Completo (`DUAL-DISPLAY-GUIDE.md`)**: Documentação detalhada do sistema dual display
- **Modificação do `all.sh`**: Atualizado para usar configurações do arquivo de configuração
- **Modificação do `d2.py`**: Atualizado para aceitar parâmetros de configuração adicionais

### Funcionalidades do Dual Display
- **Instâncias Independentes**: Cada display opera com sua própria conexão WiFi P2P
- **Nomes Distintos**: Cada display aparece como dispositivo separado na rede
- **Configurações Individuais**: Player, áudio, PIN e resolução podem ser diferentes por display
- **Redes Separadas**: Display 1 usa 192.168.173.x, Display 2 usa 192.168.174.x
- **Monitoramento Automático**: Sistema monitora e reinicia instâncias se necessário
- **Logs Separados**: Cada instância tem seu próprio arquivo de log

### Melhorias
- **Detecção Automática de Hardware**: Sistema detecta Raspberry Pi 5 automaticamente
- **Interface de Configuração**: Instalador guiado passo a passo
- **Compatibilidade Retroativa**: Single display continua funcionando como antes
- **Backup Automático**: Setup HDMI cria backup do config.txt antes de modificar

### Documentação
- README atualizado com seção de Dual Display
- Guia completo de Dual Display com exemplos e troubleshooting
- Comentários adicionais nos scripts principais

### Compatibilidade
- **Raspberry Pi 5**: Suporte completo dual display
- **Raspberry Pi 4**: Suporte experimental (limitações de hardware)
- **Outros RPi**: Single display apenas
- **Sistema Operacional**: Raspberry Pi OS (Legacy, 32-bit) recomendado

### Arquivos Novos
- `install.sh` - Instalador interativo
- `setup-hdmi.sh` - Configuração HDMI
- `all-dual.sh` - Script dual display
- `d2-multi.py` - Receiver multi-display
- `lazycast-config.conf` - Arquivo de configuração (template)
- `DUAL-DISPLAY-GUIDE.md` - Guia completo
- `make-executable.sh` - Script para tornar scripts executáveis

### Arquivos Modificados
- `all.sh` - Adicionado suporte a configuração externa
- `d2.py` - Adicionado parâmetros de configuração
- `README.md` - Adicionado seção de Dual Display
- `.gitignore` - Adicionado ignore para instâncias e configurações locais

### Notas de Instalação
1. Execute `sudo ./install.sh` para configuração inicial
2. Execute `sudo ./setup-hdmi.sh` para configurar HDMI (requer reboot)
3. Use `./all.sh` para single display ou `./all-dual.sh` para dual display
4. Edite `lazycast-config.conf` para ajustes manuais

### Requisitos Adicionais para Dual Display
- Raspberry Pi 5 (recomendado)
- Duas saídas HDMI conectadas
- Largura de banda WiFi suficiente (50Mbps+ por display)
- Memória RAM adequada (2GB mínimo, 4GB recomendado)

### Limitações Conhecidas
- Interferência WiFi possível entre duas conexões P2P
- Performance pode variar dependendo da largura de banda disponível
- Alguns dispositivos Android podem ter suporte limitado
- HDCP não suportado (como na versão original)

### Roadmap Futuro
- Suporte para mais de 2 displays
- Interface gráfica de configuração
- Balanceamento automático de carga
- Monitoramento de performance em tempo real
- Suporte MICE aprimorado para dual display