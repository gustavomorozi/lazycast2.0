# LazyCast - Estender a tela do Windows para o Raspberry Pi (Tela 1 e Tela 2).
#
# Captura cada monitor VIRTUAL (driver Virtual Display Driver) e envia como vídeo H.264 pela rede
# para as portas do Pi. No Pi, cada porta é uma tela (SCREEN1_SOURCE="stream:5004", ...).
#
# Uso:   estender-tela.ps1 [-Iniciar | -Parar | -Status] [-Pi 192.168.0.43] [-Telas 2]
#                          [-Portas 5004,5006] [-Fps 30] [-Bitrate 6M] [-Encoder auto|qsv|nvenc|x264]
param(
    [switch]$Iniciar, [switch]$Parar, [switch]$Status,
    [string]$Pi = '',
    [int]$Telas = 2,
    [int[]]$Portas = @(5004, 5006),
    [int]$Fps = 30,
    [string]$Bitrate = '6M',
    [ValidateSet('auto', 'qsv', 'nvenc', 'x264')][string]$Encoder = 'auto'
)
$pasta = $PSScriptRoot
$ipFile = Join-Path $pasta 'pi-ip.txt'
$pidFile = Join-Path $pasta 'estender.pids'
$log = Join-Path $pasta 'estender-log.txt'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')

function Log($t) { $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t; Write-Host $l; Add-Content -Path $log -Value $l -Encoding UTF8 }

function Parar-Tudo {
    if (Test-Path $pidFile) {
        foreach ($id in (Get-Content $pidFile)) {
            if ($id -match '^\d+$') { Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue }
        }
        Remove-Item $pidFile -Force
        Log 'Transmissão parada.'
    } else { Log 'Nada em execução.' }
}

if ($Parar) { Parar-Tudo; exit 0 }

# ---------- IP do Raspberry Pi (parâmetro > pi-ip.txt > pergunta uma vez e guarda)
if (-not $Parar -and -not $Status -and -not $Pi) {
    if (Test-Path $ipFile) { $Pi = (Get-Content $ipFile -Raw).Trim() }
    if (-not $Pi) {
        $Pi = (Read-Host 'IP do Raspberry Pi (painel LazyCast > Configurações; pode informar cabo e Wi-Fi separados por vírgula)').Trim()
        if ($Pi -notmatch '^\d{1,3}(\.\d{1,3}){3}([,; ]+\d{1,3}(\.\d{1,3}){3})*$') { Write-Host 'IP inválido.'; exit 1 }
        Set-Content -Path $ipFile -Value $Pi
    }
}
# Aceita vários IPs separados por vírgula (cabo e Wi-Fi do Pi) e usa o primeiro que responde:
# a tela estendida funciona igual por cabo Ethernet ou por roteador Wi-Fi.
if ($Pi -match ',') {
    $candidatos = @($Pi -split '[,; ]+' | Where-Object { $_ })
    $Pi = $candidatos[0]
    foreach ($c in $candidatos) { if (Test-Connection -ComputerName $c -Count 1 -Quiet -ErrorAction SilentlyContinue) { $Pi = $c; break } }
    Write-Host "Usando o Pi em $Pi"
}
if (-not $Parar -and -not $Status -and $Pi -and -not (Test-Connection -ComputerName $Pi -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
    Write-Host "Aviso: o Pi ($Pi) não respondeu ao ping. Confira o IP no painel do Pi e se o PC está na mesma rede (cabo ou Wi-Fi)." -ForegroundColor Yellow
}
if ($Status) {
    if (Test-Path $pidFile) {
        foreach ($id in (Get-Content $pidFile)) { $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue; "{0}: {1}" -f $id, $(if ($p) { 'transmitindo' } else { 'parado' }) }
    } else { 'Nada em execução.' }
    exit 0
}

# ---------- telas virtuais (não principais), da esquerda para a direita, em pixels reais
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class LcDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][LcDpi]::SetProcessDPIAware()
# Modo REAL (pixels físicos) de cada tela: o Screen.Bounds do .NET devolve medidas escaladas (x1,25) para
# monitores com DPI diferente do principal, o que fazia o ffmpeg capturar fora do desktop.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class LcRD {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
}
"@
function Modo-Real($dev) {
    $dm = New-Object LcRD+DEVMODE
    $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($dm)
    if ([LcRD]::EnumDisplaySettings($dev, -1, [ref]$dm) -and $dm.dmPelsWidth -gt 0) {
        return [pscustomobject]@{ DeviceName = $dev; X = $dm.dmPositionX; Y = $dm.dmPositionY; W = $dm.dmPelsWidth; H = $dm.dmPelsHeight }
    }
    return $null
}
$virtuais = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | ForEach-Object { Modo-Real $_.DeviceName } | Where-Object { $_ } | Sort-Object X)
if ($virtuais.Count -lt $Telas) {
    Log ("Só há {0} tela(s) virtual(is) ativa(s); preciso de {1}. Rode ativar-telas-virtuais.bat e ajuste a resolução." -f $virtuais.Count, $Telas)
    exit 1
}
if ($Portas.Count -lt $Telas) { Log 'Portas insuficientes para o número de telas.'; exit 1 }

# ---------- escolha do codificador (QuickSync da Intel por padrão; x264 por CPU como reserva)
function Testa-Encoder($nome) {
    $a = switch ($nome) {
        'qsv'   { @('-c:v', 'h264_qsv') }
        'nvenc' { @('-c:v', 'h264_nvenc') }
        'x264'  { @('-c:v', 'libx264') }
    }
    & ffmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=10' -frames:v 5 @a -f null - 2>$null
    return ($LASTEXITCODE -eq 0)
}
if ($Encoder -eq 'auto') {
    $Encoder = 'x264'
    foreach ($e in 'nvenc', 'qsv') { if (Testa-Encoder $e) { $Encoder = $e; break } }
}
Log "Codificador: $Encoder"
$enc = switch ($Encoder) {
    'qsv'   { @('-c:v', 'h264_qsv', '-preset', 'veryfast', '-b:v', $Bitrate, '-maxrate', $Bitrate, '-g', "$Fps", '-look_ahead', '0', '-bf', '0') }
    'nvenc' { @('-c:v', 'h264_nvenc', '-preset', 'p1', '-tune', 'll', '-b:v', $Bitrate, '-maxrate', $Bitrate, '-g', "$Fps", '-bf', '0') }
    'x264'  { @('-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-b:v', $Bitrate, '-maxrate', $Bitrate, '-bufsize', '2M', '-g', "$Fps", '-pix_fmt', 'yuv420p') }
}

Parar-Tudo | Out-Null
$ids = @()
for ($i = 0; $i -lt $Telas; $i++) {
    $b = $virtuais[$i]
    $destino = "udp://${Pi}:$($Portas[$i])?pkt_size=1316"
    $args = @('-hide_banner', '-loglevel', 'warning', '-f', 'gdigrab', '-framerate', "$Fps",
              '-offset_x', "$($b.X)", '-offset_y', "$($b.Y)", '-video_size', "$($b.W)x$($b.H)",
              '-draw_mouse', '1', '-i', 'desktop') + $enc + @('-f', 'mpegts', $destino)
    $p = Start-Process -FilePath ffmpeg -ArgumentList $args -WindowStyle Hidden -PassThru `
         -RedirectStandardError (Join-Path $pasta "estender-tela$($i + 1).log")
    $ids += $p.Id
    Log ("Tela {0}: monitor virtual {1} ({2}x{3} em {4},{5}) -> {6}  (PID {7})" -f ($i + 1), $b.DeviceName, $b.W, $b.H, $b.X, $b.Y, $destino, $p.Id)
}
$ids | Set-Content $pidFile
Log 'Transmitindo. Para parar: estender-parar.bat'

