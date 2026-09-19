# Miracast over Infrastructure (MICE)

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

