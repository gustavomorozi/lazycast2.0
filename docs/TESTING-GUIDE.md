# Guia de Teste do LazyCast Dual Display

## Teste em Ambiente Windows (Desenvolvimento)

Como o LazyCast foi projetado para Raspberry Pi/Linux, o teste em ambiente Windows é limitado a verificação de sintaxe e estrutura de código.

### Testes Automáticos Disponíveis

#### 1. Teste de Sintaxe Python
```bash
python3 -m py_compile d2.py
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
- Raspberry Pi 5 (único modelo suportado)
- Raspberry Pi OS Bookworm (64-bit)
- Fonte de alimentação adequada
- Cabo HDMI conectado a monitor/TV
- Dispositivo Windows 10/11 ou Android para teste

### Passo a Passo de Teste

#### 1. Instalação
```bash
cd ~/
git clone https://github.com/gustavomorozi/lazycast2.0
cd lazycast2.0

# O instalador cuida de tudo sozinho: instala as dependências via apt, ajusta permissões,
# configura o HDMI (dual display no Pi 5) e instala o serviço systemd.
sudo ./install.sh

# Escolha modo (Single/Dual Display), nomes dos displays e saída de áudio quando perguntado.
# --yes instala sem perguntas (padrões: single display); --dual escolhe dual display.
```

#### 2. Teste de Ambiente
```bash
# Verificar se ambiente está pronto
./test-environment.sh

# Verificar dependências
./check_dependencies.sh

# Testar sintaxe dos scripts
./test-syntax.sh
```

#### 3. Teste Manual (Single Display)
```bash
# Iniciar LazyCast manualmente
./all.sh
```

**O que verificar:**
- Mensagem "The display is ready" aparece
- Nome do display é mostrado corretamente
- Sem erros visíveis no terminal
- Interface WiFi P2P é criada

#### 4. Teste de Conexão
1. No dispositivo Windows:
   - Abrir "Configurações" > "Sistema" > "Tela" > "Conectar a um display sem fio"
   - Procurar pelo nome do display configurado
   - Por padrão (`LAZYCAST_AUTH=pbc`) conecta sem digitar PIN; se `LAZYCAST_AUTH=pin` estiver ativo, use o PIN de `LAZYCAST_PIN` no `lazycast-config.conf`

2. No dispositivo Android:
   - Abrir "Configurações" > "Tela" > "Cast"
   - Procurar pelo nome do display
   - Conectar

**O que verificar:**
- Conexão é estabelecida com sucesso
- Vídeo aparece no monitor conectado ao Pi
- Áudio é reproduzido corretamente
- Latência é aceitável (<500ms)

#### 5. Teste de Dual Display (Pi 5)
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

#### 6. Teste de Serviço Automático
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

# Monitorar o estado
./lazycast-status.sh

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
# Verificar o estado
./lazycast-status.sh

# O serviço reinicia sozinho (Restart=on-failure); se não subir, veja o log
journalctl -u lazycast -n 50
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
- [✓/✗] Instalação (install.sh)
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