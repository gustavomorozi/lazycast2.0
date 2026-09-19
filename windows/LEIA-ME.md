# LazyCast no Windows: estender a tela para o Raspberry Pi

Cria até **duas telas virtuais** no Windows e envia cada uma pela rede (Wi-Fi ou Ethernet) para o Raspberry Pi,
que as mostra na Tela 1 e na Tela 2 (ou na prévia do painel, se não houver monitor HDMI).

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
- Wi-Fi: se o PC e o Pi estiverem na mesma rede, funciona sem cabo; com Ethernet o caminho é o mesmo (só muda o IP).
- Logs: `estender-tela1.log` e `estender-tela2.log` nesta pasta.
- Para desfazer: `estender-parar.bat` e desinstale o driver pelo "VDD Control". Uma cópia do
  `vdd_settings.xml` original fica em `vdd_settings.xml.lazycast-backup`.
