# Guia de Dual Display - LazyCast

## Visão Geral

O LazyCast Dual Display permite que o Raspberry Pi 5 funcione como dois receptores de display wireless independentes, um para cada saída HDMI. Isso é ideal para configurações onde você precisa projetar conteúdo em dois monitores diferentes de fontes diferentes.

## Instalação

### 1. Clonar e Compilar

```bash
cd ~/repositorios
git clone https://github.com/gustavomorozi/lazycast2.0
cd lazycast2.0
make
```

### 2. Executar Instalador

```bash
sudo ./install.sh
```

O instalador irá guiá-lo através das seguintes opções:

1. **Modo de Display**: Escolha entre Single Display (1) ou Dual Display (2)
2. **Nomes dos Displays**: Configure nomes distintos para cada display
3. **Player**: Escolha o player de vídeo (player1, player2, omxplayer, VLC)
4. **Áudio**: Configure a saída de áudio (HDMI, 3.5mm, ALSA)

### 3. Configurar HDMI

```bash
sudo ./setup-hdmi.sh
```

Este script configura o `/boot/config.txt` para suportar duas saídas HDMI no Raspberry Pi 5. **Reboot é necessário após esta etapa.**

## Uso

### Single Display (Padrão)

```bash
./all.sh
```

### Dual Display

```bash
./all-dual.sh
```

O script `all-dual.sh` irá:
- Criar diretórios separados para cada instância
- Iniciar duas instâncias independentes do LazyCast
- Configurar redes P2P separadas para cada display
- Monitorar e reiniciar instâncias se necessário

## Configuração Manual

Edite o arquivo `lazycast-config.conf`:

```bash
nano lazycast-config.conf
```

### Configurações Principais

```bash
# Modo de operação
DISPLAY_MODE=2  # 1 = single, 2 = dual

# Display 1 (HDMI-1)
DISPLAY1_NAME="MeuPi-Display1"
DISPLAY1_IP="192.168.173.1"
DISPLAY1_DHCP_START="192.168.173.80"
DISPLAY1_DHCP_END="192.168.173.80"
DISPLAY1_SOUND_OUTPUT=2
DISPLAY1_PLAYER_SELECT=2

# Display 2 (HDMI-2)
DISPLAY2_NAME="MeuPi-Display2"
DISPLAY2_IP="192.168.174.1"
DISPLAY2_DHCP_START="192.168.174.80"
DISPLAY2_DHCP_END="192.168.174.80"
DISPLAY2_SOUND_OUTPUT=2
DISPLAY2_PLAYER_SELECT=2
```

## Solução de Problemas

### Problema: Apenas um display aparece

**Solução**: Verifique se o modo dual está configurado:
```bash
cat lazycast-config.conf | grep DISPLAY_MODE
```

Deve mostrar `DISPLAY_MODE=2`.

### Problema: Conflito de interfaces WiFi

**Solução**: Certifique-se de que não há outros processos WiFi P2P rodando:
```bash
sudo wpa_cli interface
```

Se houver interfaces P2P antigas, remova-as:
```bash
sudo wpa_cli -i<p2p-interface> p2p_group_remove <p2p-interface>
```

### Problema: Display 2 não funciona

**Solução**: Verifique os logs:
```bash
cat lazycast_instance_display2/lazycast_display2.log
```

### Problema: Baixa performance

**Solução**: 
- Use WiFi 5GHz se disponível
- Reduza a resolução nos dispositivos de origem
- Certifique-se de que há largura de banda suficiente para duas conexões

### Problema: Configuração HDMI não aplicada

**Solução**: Verifique o `/boot/config.txt`:
```bash
cat /boot/config.txt | grep hdmi
```

Reboot se necessário:
```bash
sudo reboot
```

## Arquitetura

### Estrutura de Diretórios

```
lazycast2.0/
├── all.sh                    # Script single display (modificado)
├── all-dual.sh              # Script dual display (novo)
├── install.sh               # Instalador interativo (novo)
├── setup-hdmi.sh            # Configuração HDMI (novo)
├── lazycast-config.conf     # Arquivo de configuração (novo)
├── d2.py                    # Receiver principal (modificado)
├── d2-multi.py             # Receiver multi-display (novo)
├── lazycast_instance_display1/  # Instância display 1
│   ├── d2.py
│   ├── player.bin
│   ├── h264.bin
│   └── lazycast_display1.log
└── lazycast_instance_display2/  # Instância display 2
    ├── d2.py
    ├── player.bin
    ├── h264.bin
    └── lazycast_display2.log
```

### Fluxo de Rede

1. **Display 1**: Usa rede P2P `192.168.173.x`
2. **Display 2**: Usa rede P2P `192.168.174.x`
3. Cada display tem seu próprio servidor DHCP
4. Cada display opera independentemente

## Performance e Recomendações

### Requisitos de Hardware

- **Mínimo**: Raspberry Pi 4 (com limitações)
- **Recomendado**: Raspberry Pi 5
- **Memória**: Mínimo 2GB, recomendado 4GB+
- **WiFi**: WiFi 5GHz recomendado para dual display

### Requisitos de Rede

- **Largura de banda**: Mínimo 50Mbps por display
- **Latência**: Menor é melhor para interatividade
- **Interferência**: Evite outros dispositivos WiFi próximos

### Otimizações

1. **Use Player2** para melhor handling de imagens estáticas
2. **Reduza resolução** se houver lag
3. **Use cabo Ethernet** se possível para MICE
4. **Desative WiFi scanning** durante operação

## Inicialização Automática

### Single Display

Adicione ao `/etc/xdg/lxsession/LXDE-pi/autostart`:
```bash
@lxterminal -l --working-directory=/home/pi/lazycast2.0 -e ./all.sh
```

### Dual Display

Adicione ao `/etc/xdg/lxsession/LXDE-pi/autostart`:
```bash
@lxterminal -l --working-directory=/home/pi/lazycast2.0 -e ./all-dual.sh
```

## Suporte e Contribuições

Para problemas específicos do dual display:
1. Verifique os logs em `lazycast_instance_display*/`
2. Teste primeiro o modo single display
3. Verifique configurações de hardware
4. Consulte o README principal para problemas gerais

## Limitações Conhecidas

1. **WiFi Interference**: Duas conexões P2P podem causar interferência
2. **Performance**: GPU pode ter dificuldade com 1080p60 em dual display
3. **Android**: Suporte limitado em dispositivos Android
4. **HDCP**: Não suportado (como no single display)

## Roadmap Futuro

- [ ] Suporte para mais de 2 displays
- [ ] Balanceamento automático de carga
- [ ] Interface gráfica de configuração
- [ ] Suporte MICE melhorado para dual display
- [ ] Monitoramento de performance em tempo real