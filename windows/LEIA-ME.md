# LazyCast no Windows: estender a tela para o Raspberry Pi

Cria até **duas telas virtuais** no Windows e envia cada uma pela rede (Wi-Fi ou Ethernet) para o Raspberry Pi,
que as mostra na Tela 1 e na Tela 2 (ou na prévia do painel, se não houver monitor HDMI).

## Programa: `LazyCast.exe`

Dê dois cliques em `LazyCast.exe`. É um `.exe` de verdade (escrito em Python, compilado com PyInstaller) —
não abre PowerShell nem console nenhum, e aparece como `LazyCast` no Gerenciador de Tarefas, não como
`powershell.exe`/`python.exe`. Não precisa instalar Python nem nada a mais para *usar* o programa.

Na janela:

- **Ligar tela virtual:** cria 1 ou 2 telas virtuais, estende a área de trabalho e envia ao Pi (IP do Pi: cabo e/ou
  Wi-Fi, separados por vírgula).
- **Desligar:** para o envio e solta as telas virtuais da área de trabalho (os monitores continuam no driver;
  "Ligar" as traz de volta). Com a caixa marcada, zera também os monitores do driver; nesse caso o driver só os
  recria depois de reiniciar o notebook.
- **Instalar driver:** baixa o Virtual Display Driver 25.7.23 do GitHub oficial, confere o SHA-256 e instala com o
  `devcon.exe` da própria Microsoft (sem abrir mais nenhuma janela); o Windows pede a sua permissão de
  administrador, só para esse comando. Se o driver já estiver instalado, o botão some e aparece o aviso.
- **Desinstalar driver:** remove o driver com o `devcon.exe`/`pnputil` (permissão de administrador) e para o envio.
- **Bandeja do sistema:** minimizar deixa o programa rodando ali do lado do relógio (o envio continua). Fechar a
  janela (ou "Sair" no ícone da bandeja) para o envio de verdade e solta as telas virtuais — elas não ficam mais
  aparecendo em Configurações > Vídeo depois que você fecha o programa.
- **Conectar por Miracast:** abre o painel Transmitir do Windows (como Win+K); escolha o receptor
  `LazyCast-<animal>` da lista.

## Passo a passo

1. **No Raspberry Pi** (painel LazyCast → Configurações → *Fonte de cada tela*): escolha **Rede (UDP 5004)** para a
   Tela 1 e **Rede (UDP 5006)** para a Tela 2, ou edite `lazycast-config.conf`:

   ```
   SCREEN1_SOURCE="stream:5004"
   SCREEN2_SOURCE="stream:5006"
   ```

2. **No Windows:** abra `LazyCast.exe` e clique em **Instalar driver** (ou instale o "Virtual Display Driver",
   projeto VirtualDrivers, do jeito que preferir). A instalação pede permissão de administrador: aprove você mesmo.
   Este pacote não altera modo de teste nem Secure Boot.
3. Informe o IP do Pi, escolha 1 ou 2 telas e clique em **Ligar tela virtual**.
4. Para encerrar: **Desligar**, ou feche a janela.

## Requisitos e observações

- `ffmpeg` no PATH. Codificador automático: Intel QuickSync (`h264_qsv`), depois NVENC, depois `libx264`.
- Fluxo: MPEG-TS sobre UDP, sem áudio, portas 5004 (tela virtual 1) e 5006 (tela virtual 2). Bitrate padrão 3 Mbps
  (testado no Wi-Fi 2,4 GHz: 6 Mbps causava perda de pacote e travadinhas).
- Latência: o Pi usa buffer de 300 ms (`LAZYCAST_STREAM_CACHING` no `lazycast-config.conf`).
- **Cabo ou Wi-Fi (roteador):** funciona nos dois. O painel do Pi (Configurações > Fonte de cada tela) mostra o IP de
  cada interface, por exemplo `Cabo 192.168.0.50 · Wi-Fi 192.168.0.43`. O programa aceita os dois separados por
  vírgula e usa o primeiro que responder ao ping. Cabo direto PC↔Pi (sem roteador): configure IPs fixos nos dois
  lados, na mesma faixa (ex.: 10.0.0.1 e 10.0.0.2).
- Logs: `estender-tela1.log` e `estender-tela2.log` nesta pasta.
- Para desfazer: **Desligar** com a caixa marcada, ou **Desinstalar driver**.

## Para mexer no código (`build.ps1`)

O `.exe` já vem pronto no repositório; isto só é necessário se você alterar `lazycast_windows.py`:

```powershell
cd windows
.\build.ps1
```

Isso instala as dependências (`pystray`, `Pillow`, `pywin32`, `pyinstaller`) e gera `LazyCast.exe` de novo.
