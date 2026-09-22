# LazyCast no Windows: estender a tela para o Raspberry Pi

Cria até **duas telas virtuais** no Windows e envia cada uma pela rede (Wi-Fi ou Ethernet) para o Raspberry Pi,
que as mostra na Tela 1 e na Tela 2 (ou na prévia do painel, se não houver monitor HDMI).

## Programa com janela: `LazyCast.bat`

Dê dois cliques em `LazyCast.bat`. Na janela:

- **Ligar tela virtual:** cria 1 ou 2 telas virtuais, estende a área de trabalho e envia ao Pi (IP do Pi: cabo e/ou Wi-Fi, separados por vírgula).
- **Desligar:** para o envio e solta as telas virtuais da área de trabalho (os monitores continuam no driver; "Ligar" as traz de volta). Com a caixa marcada, zera também os monitores do driver; nesse caso o driver só os recria depois de reiniciar o notebook.
- **Instalar driver:** baixa o Virtual Display Driver 25.7.23 do GitHub oficial, confere o SHA-256 e abre o instalador; o Windows pede a sua permissão de administrador. Se o driver já estiver instalado, o botão some e aparece o aviso.
- **Bandeja do sistema:** minimizar deixa o programa rodando ali do lado do relógio (o envio continua).
  Fechar a janela (ou "Sair" no ícone da bandeja) para o envio de verdade e solta as telas virtuais —
  elas não ficam mais aparecendo em Configurações > Vídeo depois que você fecha o programa.
- **Desinstalar driver:** remove o driver com o `pnputil` (o Windows pede a sua permissão de administrador) e para o envio.
- **Conectar por Miracast:** abre o painel Transmitir do Windows (como Win+K); escolha o receptor `LazyCast-<animal>` da lista.

Os passos abaixo (`.bat` separados) continuam valendo se preferir linha de comando.

## Passo a passo

1. **No Raspberry Pi** (painel LazyCast → Configurações → *Fonte de cada tela*): escolha **Rede (UDP 5004)** para a
   Tela 1 e **Rede (UDP 5006)** para a Tela 2, ou edite `lazycast-config.conf`:

   ```
   SCREEN1_SOURCE="stream:5004"
   SCREEN2_SOURCE="stream:5006"
   ```

2. **No Windows, instale o driver de monitor virtual** ("Virtual Display Driver", projeto VirtualDrivers, assinado).
   A instalação pede permissão de administrador: faça-a você mesmo, seguindo as instruções do projeto do driver.
   Este pacote não altera modo de teste nem Secure Boot.
3. Rode `configurar-telas-virtuais.bat`: pede 2 monitores ao driver, estende a área de trabalho e deixa cada tela
   virtual em 1920x1080 a 60 Hz.
4. Rode `estender-iniciar.bat`. Na primeira vez ele pergunta o IP do Raspberry Pi e guarda em `pi-ip.txt`.
   (Também aceita `estender-tela.ps1 -Pi 192.168.0.43`.)
5. Para encerrar: `estender-parar.bat`. Estado: `estender-tela.ps1 -Status`.

## Requisitos e observações

- `ffmpeg` no PATH. Codificador automático: Intel QuickSync (`h264_qsv`), depois NVENC, depois `libx264`.
- Fluxo: MPEG-TS sobre UDP, sem áudio, portas 5004 (tela virtual 1) e 5006 (tela virtual 2).
- Latência: o Pi usa buffer de 300 ms (`LAZYCAST_STREAM_CACHING` no `lazycast-config.conf`).
- **Cabo ou Wi-Fi (roteador):** funciona nos dois. O painel do Pi (Configurações > Fonte de cada tela) mostra o IP de
  cada interface, por exemplo `Cabo 192.168.0.50 · Wi-Fi 192.168.0.43`. Use o IP da conexão que o PC também usa.
  O script aceita os dois IPs e escolhe o primeiro que responde: `estender-tela.ps1 -Pi 192.168.0.50,192.168.0.43`.
  **Padrão agora é 3 Mbps** (`-Bitrate 3M`): testado no Wi-Fi 2,4 GHz — com 6 Mbps apareciam perdas de pacote
  (travadinhas/atraso), com 3 Mbps não. Por cabo dá mais folga: `-Bitrate 12M`. Wi-Fi fraco: tente `-Fps 15` ou `-Bitrate 2M`.
  Cabo direto PC↔Pi (sem roteador): configure IPs fixos nos dois lados, na mesma faixa (ex.: 10.0.0.1 e 10.0.0.2).
- Logs: `estender-tela1.log` e `estender-tela2.log` nesta pasta.
- Para desfazer: `estender-parar.bat` e desinstale o driver pelo "VDD Control". Uma cópia do
  `vdd_settings.xml` original fica em `vdd_settings.xml.lazycast-backup`.
