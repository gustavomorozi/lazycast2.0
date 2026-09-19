# Dicas

Defina a resolução no lado da fonte. lazycast anuncia todas as resoluções possíveis independentemente da resolução de renderização atual. Portanto, você pode querer alterar a resolução (na fonte) para corresponder à resolução real do display conectado ao Pi.

Modifique parâmetros na seção "settings" em ``d2.py`` para alterar a porta de saída de som (hdmi/3.5mm) e o player preferido.

As resoluções máximas suportadas são 1920x1080p60 e 1920x1200p30. A GPU do Pi pode ter dificuldade para lidar com 1920x1080p60, o que resulta em alta latência. Neste caso, reduza o FPS para 1920x1080p50.

Você pode esconder o cursor do Pi usando ``unclutter -idle 3``. Veja [este post](https://forums.raspberrypi.com/viewtopic.php?t=234879#p1437648).

Depois que o Pi se conecta à fonte, ele tem um endereço IP de ``192.168.173.1`` e esta conexão pode ser reutilizada para outros propósitos como SSH. Por outro lado, como eles estão na mesma sub-rede, precauções devem ser tomadas para evitar acesso não autorizado ao Pi.

Dois players internos foram escritos para Raspberry Pi 3. VLC, omxplayer ou gstreamer podem ser usados em outras plataformas. (Veja [aqui](https://gstreamer.freedesktop.org/documentation/installing/on-linux.html) para detalhes da instalação do gstreamer.)

**É muito importante que nenhum scanning WiFi em segundo plano ocorra durante o cast. No Raspberry Pi, lazycast desabilitará automaticamente ``lxpanel`` durante o cast (para parar o plugin ``lxplug-network`` de escanear a rede), e reabilitará ``lxpanel`` após o cast ser terminado. Você pode querer desabilitar ``wlan0`` completamente (``sudo ifconfig wlan0 down``) especialmente se ``wlan0`` não estiver conectado a nenhuma rede no momento (e scanning periódico será acionado neste caso). Você pode verificar que nenhum scanning WiFi em segundo plano acontece executando ``iw event`` em um segundo terminal (e nenhum evento deve ser mostrado). [Este post](https://forums.raspberrypi.com/viewtopic.php?t=250729#p1772473) tem mais informações.

Para redirecionar entradas de mouse e teclado no Pi, primeiro instale evdev (``pip install evdev``) e então defina ``enable_mouse_keyboard`` para ``1`` em ``d2.py``. Você também precisa permitir entradas de mouse e teclado no PC.

