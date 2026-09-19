# Guia de Teste do LazyCast Dual Display

## Teste em Ambiente Windows (Desenvolvimento)

Como o LazyCast foi projetado para Raspberry Pi/Linux, o teste em ambiente Windows é limitado a verificação de sintaxe e estrutura de código.

### Testes Automáticos Disponíveis

#### 1. Teste de Sintaxe Python
```bash
python3 -m py_compile d2.py
python3 -m py_compile d2-multi.py
python3 -m py_compile project.py
```

#### 2. Teste de Sintaxe Bash
```bash
bash -n all.sh
bash -n all-dual.sh
bash -n install.sh
```

#### 3. Scripts de Teste Automatizado
```bash
./test-syntax.sh          # Testa sintaxe de todos os scripts bash
./test-environment.sh    # Verifica ambiente do sistema
./check_dependencies.sh   # Verifica dependências
```

## Teste em Hardware Real (Raspberry Pi)

### Pré-requisitos
- Raspberry Pi (preferencialmente Pi 5 para dual display)
- Raspberry Pi OS (Legacy, 32-bit)
- Fonte de alimentação adequada
- Cabo HDMI conectado a monitor/TV
- Dispositivo Windows 10/11 ou Android para teste

### Passo a Passo de Teste

#### 1. Preparação do Sistema
```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências básicas
sudo apt install python3 python3-pip git cmake -y

# Instalar dependências do LazyCast
sudo apt install libx11-dev libasound2-dev libavformat-dev libavcodec-dev python3-evdev -y

# Clonar repositório
cd ~/
git clone https://github.com/gustavomorozi/lazycast2.0
cd lazycast2.0
```

#### 2. Compilação
```bash
# Compilar bibliotecas do sistema
cd /opt/vc/src/hello_pi/libs/ilclient/
sudo make
cd /opt/vc/src/hello_pi/hello_video
sudo make

# Compilar LazyCast
cd ~/lazycast2.0
make
```

#### 3. Configuração de HDMI (Pi 5)
```bash
# Executar script de configuração HDMI
sudo ./setup-hdmi.sh

# Reboot
sudo reboot
```

#### 4. Instalação e Configuração
```bash
cd ~/lazycast2.0

# Executar instalador
sudo ./install.sh

# Escolher opções:
# - Modo: Single Display (1) ou Dual Display (2)
# - Nomes dos displays
# - Player: player2 (recomendado)
# - Áudio: ALSA (2)
```

#### 5. Teste de Ambiente
```bash
# Verificar se ambiente está pronto
./test-environment.sh

# Verificar dependências
./check_dependencies.sh

# Testar sintaxe dos scripts
./test-syntax.sh
```

#### 6. Teste Manual (Single Display)
```bash
# Iniciar LazyCast manualmente
./all.sh
```

**O que verificar:**
- Mensagem "The display is ready" aparece
- Nome do display é mostrado corretamente
- Sem erros visíveis no terminal
- Interface WiFi P2P é criada

#### 7. Teste de Conexão
1. No dispositivo Windows:
   - Abrir "Configurações" > "Sistema" > "Tela" > "Conectar a um display sem fio"
   - Procurar pelo nome do display configurado
   - Conectar sem PIN (sistema foi removido)

2. No dispositivo Android:
   - Abrir "Configurações" > "Tela" > "Cast"
   - Procurar pelo nome do display
   - Conectar

**O que verificar:**
- Conexão é estabelecida com sucesso
- Vídeo aparece no monitor conectado ao Pi
- Áudio é reproduzido corretamente
- Latência é aceitável (<500ms)

#### 8. Teste de Dual Display (Pi 5)
```bash
# Parar instância single se estiver rodando
# Ctrl+C no terminal do all.sh

# Iniciar dual display
./all-dual.sh
```

**O que verificar:**
- Duas instâncias são iniciadas
- Nomes diferentes para cada display
- Ambos aparecem na lista de dispositivos
- Conexão simultânea funciona
- Cada display em HDMI diferente

#### 9. Teste de Serviço Automático
```bash
# Instalar serviço systemd
sudo ./install-service.sh

# Verificar status
sudo systemctl status lazycast

# Ver logs
journalctl -u lazycast -f

# Reboot e verificar se inicia automaticamente
sudo reboot
```

**Após reboot:**
- Verificar notificações na interface gráfica
- Verificar status com `./lazycast-status.sh`
- Testar conexão com dispositivo externo

### Testes Específicos

#### Teste de Estabilidade
```bash
# Deixar rodando por várias horas
./all.sh

# Monitorar com health check
./player_health_check.sh

# Verificar logs periodicamente
tail -f lazycast-background.log
```

#### Teste de Re-conexão
1. Conectar dispositivo
2. Desconectar
3. Reconectar
4. Verificar se funciona sem problemas

#### Teste de Reinicialização
1. Conectar dispositivo
2. Reboot do Pi
3. Verificar se reconecta automaticamente

#### Teste de Múltiplos Dispositivos
1. Conectar dispositivo A
2. Desconectar
3. Conectar dispositivo B
4. Verificar se funciona com diferentes dispositivos

### Solução de Problemas

#### Se houver erro de conexão:
```bash
# Limpar informações de pareamento
./clear_pairing.sh

# Tentar novamente
./all.sh
```

#### Se player parar:
```bash
# Verificar saúde do player
./player_health_check.sh

# O sistema deve reiniciar automaticamente
```

#### Se WiFi não funcionar:
```bash
# Verificar interface WiFi
iw dev

# Verificar wpa_supplicant
sudo wpa_cli interface

# Limpar interfaces P2P antigas
./removep2p.sh
```

### Critérios de Sucesso

O LazyCast está funcionando corretamente se:

- ✅ Scripts não têm erros de sintaxe
- ✅ Ambiente passa todos os testes do `test-environment.sh`
- ✅ LazyCast inicia sem erros
- ✅ Display aparece na lista de dispositivos
- ✅ Conexão é estabelecida com sucesso
- ✅ Vídeo e áudio funcionam corretamente
- ✅ Latência é aceitável (<500ms)
- ✅ Re-conexão funciona sem problemas
- ✅ Serviço automático funciona após reboot
- ✅ Notificações aparecem na interface gráfica

### Relatório de Teste

Use este template para documentar resultados:

```
Data: [DATA]
Hardware: [MODELO DO PI]
Software: [VERSÃO DO OS]
Modo Testado: [Single/Dual]

Resultados:
- [✓/✗] Sintaxe Python
- [✓/✗] Sintaxe Bash  
- [✓/✗] Ambiente do sistema
- [✓/✗] Compilação
- [✓/✗] Inicialização manual
- [✓/✗] Conexão Windows
- [✓/✗] Conexão Android
- [✓/✗] Vídeo
- [✓/✗] Áudio
- [✓/✗] Latência
- [✓/✗] Re-conexão
- [✓/✗] Serviço automático

Problemas encontrados:
[LISTAR PROBLEMAS]

Observações:
[OBSERVAÇÕES ADICIONAIS]
```

### Teste Contínuo

Para desenvolvimento contínuo, recomenda-se:

1. **Testes de Sintaxe**: Sempre após modificar código
2. **Testes de Ambiente**: Antes de cada teste em hardware
3. **Testes Funcionais**: Após cada mudança significativa
4. **Testes de Estabilidade**: Periodicamente (longa duração)

## Contribuindo com Testes

Se você encontrar problemas ou tiver sugestões para melhorar os testes:

1. Documente o problema detalhadamente
2. Inclua logs relevantes
3. Descreva o hardware/software usado
4. Sugira melhorias nos scripts de teste
5. Abra uma issue no repositório GitHub