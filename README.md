lazycast: Um Receptor Wireless Display Simples

## LazyCast Dual Display - Suporte para Raspberry Pi 5

**NOVA FUNCIONALIDADE**: LazyCast agora suporta modo dual display para Raspberry Pi 5, permitindo dois receptores independentes, um para cada saída HDMI (HDMI-1 e HDMI-2).

# Descrição
lazycast é um receptor de display WiFi simples. Foi originalmente desenvolvido para Raspberry Pi (como display) e Windows 8.1/10 (como fonte), mas **pode** também funcionar em outras plataformas Linux e fontes Miracast. (Para outros sistemas Linux, pule a seção de preparação. Para reprodução de vídeo de fontes Android, modifique a opção ``player_select`` em ``d2.py``.) Para sistemas Windows 10, o recurso Miracast over Infrastructure (**MICE**) também é suportado, o que pode proporcionar uma melhor experiência de usuário. Em geral, lazycast não requer recompilação do wpa_supplicant para suportar várias funcionalidades p2p, e deve funcionar em um Raspberry Pi "out of the box".

# Sistema Operacional
Selecione "**Raspberry Pi OS (Legacy, 32-bit)** Uma porta do Debian Bullseye com atualizações de segurança e ambiente desktop" ao gravar o cartão SD. Debian Bookworm parece causar alguns problemas.

Em um sistema operacional novo, instale ``cmake``:
```
sudo apt install cmake
```
Clone o repositório userland do Raspberry Pi e execute ``buildme``:
```
git clone https://github.com/raspberrypi/userland
cd userland
./buildme
```
Substitua ``vc4-kms-v3d`` por ``vc4-fkms-v3d`` em ``/boot/config.txt``:
```
sudo sed -i 's/vc4-kms-v3d/vc4-fkms-v3d/g' /boot/config.txt
```
Então reinicie:
```
sudo reboot
```
(Você pode ver [este post](https://github.com/homeworkc/lazycast/issues/100#issuecomment-1003732280) para mais detalhes.)

## Compilar Binários
Instale pacotes (para compilar os players):
```
sudo apt install libx11-dev libasound2-dev libavformat-dev libavcodec-dev python3-evdev
```
Compile bibliotecas no Pi:
```
cd /opt/vc/src/hello_pi/libs/ilclient/
sudo make
cd /opt/vc/src/hello_pi/hello_video
sudo make
```
Clone este repositório (para um diretório desejado):
```
cd ~/
git clone https://github.com/homeworkc/lazycast
```
Vá para o diretório ``lazycast`` e então execute ``make``:
```
cd lazycast
make
```

# Uso

## Modo Single Display (Padrão)
Execute `./all.sh` para iniciar o receptor lazycast. Aguarde até a mensagem "The display is ready". O nome do display aparecerá após esta mensagem. Então, procure este nome no dispositivo de origem que você deseja fazer o cast. O número PIN padrão é ``31415926``.

É recomendado parar o cast pelos controles no lado da fonte (por exemplo, no PC).

## Modo Dual Display (Raspberry Pi 5)

Para usar o modo dual display com duas saídas HDMI independentes:

1. **Instalação e Configuração**:
   ```bash
   sudo ./install.sh
   ```
   
   O instalador irá:
   - Detectar automaticamente se é um Raspberry Pi 5
   - Oferecer opção entre Single Display e Dual Display
   - Configurar nomes diferentes para cada display
   - Configurar PINs diferentes para cada display
   - Configurar player e saída de áudio

2. **Configuração HDMI**:
   ```bash
   sudo ./setup-hdmi.sh
   ```
   
   Este script configura o sistema para suportar duas saídas HDMI independentes no Raspberry Pi 5.

3. **Iniciar Dual Display**:
   ```bash
   ./all-dual.sh
   ```
   
   Isso iniciará duas instâncias independentes do LazyCast:
   - **Display 1**: Nome configurado (ex: raspberrypi-Display1) - HDMI-1
   - **Display 2**: Nome configurado (ex: raspberrypi-Display2) - HDMI-2

4. **Configuração Manual**:
   
   Edite o arquivo `lazycast-config.conf` para ajustar configurações:
   ```bash
   nano lazycast-config.conf
   ```
   
   Principais configurações:
   - `DISPLAY_MODE`: 1 para single, 2 para dual
   - `DISPLAY1_NAME`: Nome do primeiro display
   - `DISPLAY2_NAME`: Nome do segundo display
   - `DISPLAY1_PIN`/`DISPLAY2_PIN`: PINs para cada display
   - `DISPLAY1_IP`/`DISPLAY2_IP`: IPs das redes P2P
   - `DISPLAY1_PLAYER_SELECT`/`DISPLAY2_PLAYER_SELECT`: Player para cada display

### Características do Dual Display:

- **Independência Total**: Cada display opera com sua própria conexão WiFi P2P
- **Nomes Distintos**: Aparecem como dispositivos separados no dispositivo de origem
- **Configurações Individuais**: Player, áudio e PIN podem ser diferentes para cada display
- **Resolução Separada**: Cada display pode ter resolução diferente
- **Simultaneidade**: Ambos os displays podem receber conteúdo simultaneamente

### Requisitos:

- Raspberry Pi 5 (recomendado para melhor performance)
- Sistema operacional atualizado
- Duas saídas HDMI conectadas
- Suficiente largura de banda WiFi para duas conexões simultâneas

# Dicas
Defina a resolução no lado da fonte. lazycast anuncia todas as resoluções possíveis independentemente da resolução de renderização atual. Portanto, você pode querer alterar a resolução (na fonte) para corresponder à resolução real do display conectado ao Pi.

Modifique parâmetros na seção "settings" em ``d2.py`` para alterar a porta de saída de som (hdmi/3.5mm) e o player preferido.

As resoluções máximas suportadas são 1920x1080p60 e 1920x1200p30. A GPU do Pi pode ter dificuldade para lidar com 1920x1080p60, o que resulta em alta latência. Neste caso, reduza o FPS para 1920x1080p50.

Para alterar o número PIN padrão, substitua a string ``31415926`` em ``all.sh`` por outro número de 8 dígitos.

Você pode esconder o cursor do Pi usando ``unclutter -idle 3``. Veja [este post](https://forums.raspberrypi.com/viewtopic.php?t=234879#p1437648).

Depois que o Pi se conecta à fonte, ele tem um endereço IP de ``192.168.173.1`` e esta conexão pode ser reutilizada para outros propósitos como SSH. Por outro lado, como eles estão na mesma sub-rede, precauções devem ser tomadas para evitar acesso não autorizado ao Pi por qualquer pessoa que conheça o número PIN.

Dois players internos foram escritos para Raspberry Pi 3. VLC, omxplayer ou gstreamer podem ser usados em outras plataformas. (Veja [aqui](https://gstreamer.freedesktop.org/documentation/installing/on-linux.html) para detalhes da instalação do gstreamer.)

**É muito importante que nenhum scanning WiFi em segundo plano ocorra durante o cast. No Raspberry Pi, lazycast desabilitará automaticamente ``lxpanel`` durante o cast (para parar o plugin ``lxplug-network`` de escanear a rede), e reabilitará ``lxpanel`` após o cast ser terminado. Você pode querer desabilitar ``wlan0`` completamente (``sudo ifconfig wlan0 down``) especialmente se ``wlan0`` não estiver conectado a nenhuma rede no momento (e scanning periódico será acionado neste caso). Você pode verificar que nenhum scanning WiFi em segundo plano acontece executando ``iw event`` em um segundo terminal (e nenhum evento deve ser mostrado). [Este post](https://forums.raspberrypi.com/viewtopic.php?t=250729#p1772473) tem mais informações.

Para redirecionar entradas de mouse e teclado no Pi, primeiro instale evdev (``pip install evdev``) e então defina ``enable_mouse_keyboard`` para ``1`` em ``d2.py``. Você também precisa permitir entradas de mouse e teclado no PC.

# Problemas Conhecidos
lazycast tenta lembrar as credenciais de pareamento para que entrar com o PIN seja necessário apenas uma vez para cada dispositivo. No entanto, este recurso não parece funcionar corretamente o tempo todo com imagens recentes do Raspbian. Portanto, o re-pareamento pode ser necessário após cada reinicialização do Raspberry Pi. Tente limpar as informações do 'lazycast' no dispositivo de origem antes de re-parear se você encontrar problemas de pareamento.

Player2 parece ter um bug de double-free que causa travamento ao reproduzir alguns vídeos. Atualmente um workaround (que monitora constantemente a vitalidade do player2) está implementado.

Latência: Limitada pela implementação do player rtp usado. (No VLC, a latência pode ser reduzida de 1200 para 300ms diminuindo o valor de cache de rede.)

Devido à natureza superlotada do espectro WiFi e uso de transmissão rtp não confiável, você pode experimentar algumas falhas de vídeo/travamento de áudio. Os players internos empregam vários mecanismos para ocultar erros de transmissão, mas ainda pode ser notável em ambientes wireless desafiadores. Interferência de outros dispositivos pode causar desconexões.

Dispositivos podem não suportar totalmente controle de backchannel e alguns pressionamentos de tecla/cliques se comportarão de forma diferente.

HDCP(proteção de conteúdo): Nem a chave nem o hardware estão disponíveis no Pi e portanto não é suportado.

<!-- Alguns dispositivos Windows 10 parecem desconectar logo após uma conexão ser estabelecida. Você pode tentar usar ``win10debug.sh`` em vez de ``all.sh`` e ver se ajuda. -->

# Iniciar no Boot

Adicione esta linha a ``/etc/xdg/lxsession/LXDE-pi/autostart``:
```
@lxterminal -l --working-directory=<caminho absoluto do lazycast> -e ./all.sh
```
Por exemplo, se lazycast está colocado sob ``~/`` (que é ``/home/pi/``, se seu nome de usuário é ``pi``), adicione a seguinte linha ao arquivo:
```
@lxterminal -l --working-directory=/home/pi/lazycast -e ./all.sh
```

# Miracast over Infrastructure

Para fontes Windows 10, Miracast over Infrastructure (MICE) é um recurso que permite transmissão de dados de tela através de Ethernet ou redes WiFi seguras. A especificação do Miracast over Infrastructure (MICE) está disponível [aqui](https://winprotocoldoc.blob.core.windows.net/productionwindowsarchives/MS-MICE/%5bMS-MICE%5d.pdf). Comparado com wifi p2p, permite conexão mais estável e menor latência. Embora MICE dependa quase inteiramente de Ethernet ou rede WiFi segura, na fase de descoberta de dispositivo, ainda requer um dispositivo wifi p2p para broadcast de beacon e frames de resposta de probe para a fonte. (No entanto, pode ser possível usar dois Pis para que um dos dois não precise ter hardware WiFi ou estar fisicamente próximo da fonte. Um Pi seria usado para transmitir o beacon enquanto o outro (que executa ``./project.py``) é usado para projetar. Para tal configuração funcionar, a variável ``hostname`` em ``mice.py`` deve ser definida para o hostname da máquina executando ``project.py``. No futuro, pode ser possível emular uma placa WiFi por HW/SW na fonte para que wifi p2p não seja necessário.)

Atualmente, este recurso foi testado funcionando com um PC Windows 10 e um Pi (com IPs atribuídos manualmente) conectados via Ethernet. Mais testes podem ser necessários, especialmente para diferentes configurações de DHCP, DNS e firewall. As portas usadas incluem mas não estão limitadas a UDP 53 (DNS), UDP 5353 (mDNS), TCP 7236 e TCP 7250. Além disso, o recurso de criptografia não está implementado ainda então deve ser usado apenas em redes confiáveis e não deve ser usado para dados sensíveis. MICE funciona em redes ipv6 mas atualmente apenas ipv4 está implementado.

## Preparação
Instale avahi-utils:
```
sudo apt install avahi-utils
```
Certifique-se de que o PC Windows 10 está na mesma rede que o Pi. Você pode tentar fazer ping no Pi a partir do PC.
NetworkManager **não** é necessário para esta versão do MICE. No entanto, usar MICE desabilitará a interface WiFi integrada. (Para restaurar a interface WiFi integrada após MICE, execute ``resetwpa.sh`` ou simplesmente reinicie.)

## Uso
Certifique-se de que não há interface p2p já criada e ``all.sh`` não está rodando. (Certifique-se de que ``all.sh`` não inicie no boot e então simplesmente reinicie.)

Execute ``./mice.sh``.

Use a aba "Connect" no Windows 10 e tente conectar ao hostname do Pi (por exemplo, raspberrypi). O Windows pode tentar conectar usando o método tradicional primeiro e portanto pode pedir PIN. Neste caso, simplesmente cancele o processo de conexão e tente novamente. Como nenhuma criptografia está implementada no momento, o prompt de PIN não deve aparecer usando MICE.

O Windows 10 atribui o nome do display de forma diferente quando usa MICE. Se o monitor conectado ao Pi for detectado com sucesso pelo PC, o nome do display (por exemplo, raspberrypi) será alterado para o nome do monitor. Se a detecção falhar, o nome do display será alterado para "Device". Após desconexão, o nome do display será alterado de volta para o hostname do Pi (por exemplo, raspberrypi).

Se você deseja executar MICE e wifi p2p simultaneamente, defina o parâmetro ``concurrent`` para ``1`` em ``newmice.py`` e use apenas ``mice.sh``. Quando há múltiplos IPs atribuídos ao Pi e mDNS não parece estar funcionando, defina manualmente a variável ``ipstr`` em ``newmice.py`` para o IP alvo do Pi e um PC tentará conectar a este IP diretamente.

# Outros
Algumas partes do player de vídeo1 foram modificadas dos códigos em https://github.com/Apress/raspberry-pi-gpu-audio-video-prog. Muitos thanks ao autor de "Raspberry Pi GPU Audio Video Programming" e, por extensão, autores do omxplayer.
O uso de qualquer parte dos códigos neste projeto em produtos comerciais é proibido.