# LazyCast (Windows) - configura os monitores virtuais do "Virtual Display Driver" para estender a tela ao Pi.
#
# Faz, de forma repetível: (1) pede N monitores virtuais ao driver, (2) deixa 1920x1080 como modo padrão,
# (3) recarrega o driver, (4) estende as telas e (5) aplica 1920x1080 a 60 Hz em cada uma.
# Pré-requisito: driver instalado (veja LEIA-ME.md). Não precisa de administrador se você já tem permissão
# de escrita na pasta do driver (o instalador padrão a concede).
#
# Uso: configurar-telas-virtuais.ps1 [-Telas 2] [-Largura 1920] [-Altura 1080] [-Hz 60]
param([int]$Telas = 2, [int]$Largura = 1920, [int]$Altura = 1080, [int]$Hz = 60)

$cfg = 'C:\VirtualDisplayDriver\vdd_settings.xml'
if (-not (Test-Path $cfg)) {
    Write-Host "Driver do monitor virtual não encontrado ($cfg). Instale-o primeiro (LEIA-ME.md, passo 2)." -ForegroundColor Yellow
    exit 1
}

# ---------- 1-2) contagem de monitores e modo padrão no arquivo do driver (com cópia de segurança)
if (-not (Test-Path "$cfg.lazycast-backup")) { Copy-Item $cfg "$cfg.lazycast-backup" -Force }
[xml]$x = Get-Content $cfg -Raw
$x.vdd_settings.monitors.count = "$Telas"
$res = $x.vdd_settings.resolutions
$modo = $res.resolution | Where-Object { $_.width -eq "$Largura" -and $_.height -eq "$Altura" } | Select-Object -First 1
if ($modo) {
    if (-not ($modo.refresh_rate | Where-Object { $_ -eq "$Hz" })) {
        $rr = $x.CreateElement('refresh_rate'); $rr.InnerText = "$Hz"; [void]$modo.AppendChild($rr)
    }
    [void]$res.RemoveChild($modo); [void]$res.InsertBefore($modo, $res.FirstChild)
} else {
    Write-Host "A resolução ${Largura}x${Altura} não está na lista do driver; mantendo a ordem original." -ForegroundColor Yellow
}
$x.Save($cfg)
Write-Host "Driver configurado para $Telas monitor(es) virtual(is), ${Largura}x${Altura}."

# ---------- 3) recarrega o driver pelo canal dele
try {
    $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'MTTVirtualDisplayPipe', [System.IO.Pipes.PipeDirection]::InOut)
    $p.Connect(3000)
    $w = New-Object System.IO.StreamWriter($p); $w.AutoFlush = $true; $w.Write('RELOAD_DRIVER'); Start-Sleep -Milliseconds 600; $p.Dispose()
    Write-Host 'Driver recarregado.'
} catch {
    Write-Host 'Não consegui recarregar o driver pelo canal dele. Abra o "VDD Control" e use Reload driver.' -ForegroundColor Yellow
}
Start-Sleep 5

# ---------- 4) estender
Start-Process -FilePath "$env:WINDIR\System32\DisplaySwitch.exe" -ArgumentList '/extend' -Wait
Start-Sleep 4

# ---------- 5) 1920x1080@60 em cada tela extra (uma por vez; em lote o Windows ignora)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class LcSM {
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
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lp);
}
"@
$extras = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary })
if ($extras.Count -eq 0) {
    Write-Host 'Nenhuma tela extra ativa. Aperte Win+P > Estender e rode este script de novo.' -ForegroundColor Yellow
    exit 1
}
foreach ($e in $extras) {
    $dm = New-Object LcSM+DEVMODE
    $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($dm)
    [void][LcSM]::EnumDisplaySettings($e.DeviceName, -1, [ref]$dm)
    $dm.dmPelsWidth = $Largura; $dm.dmPelsHeight = $Altura; $dm.dmDisplayFrequency = $Hz
    $dm.dmFields = 0x80000 -bor 0x100000 -bor 0x400000          # largura | altura | taxa
    $r = [LcSM]::ChangeDisplaySettingsEx($e.DeviceName, [ref]$dm, [IntPtr]::Zero, 1, [IntPtr]::Zero)   # 1 = grava e aplica agora
    Write-Host ("{0}: {1}x{2}@{3} Hz  ->  {4}" -f $e.DeviceName, $Largura, $Altura, $Hz, $(if ($r -eq 0) { 'ok' } else { "código $r" }))
    Start-Sleep 1
}

Write-Host ''
Write-Host 'Modos atuais (pixels reais):'
1..30 | ForEach-Object {
    $n = "\\.\DISPLAY$_"
    $d = New-Object LcSM+DEVMODE; $d.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($d)
    if ([LcSM]::EnumDisplaySettings($n, -1, [ref]$d) -and $d.dmPelsWidth -gt 0) {
        Write-Host ("  {0,-14} {1}x{2} @{3} Hz  em ({4},{5})" -f $n, $d.dmPelsWidth, $d.dmPelsHeight, $d.dmDisplayFrequency, $d.dmPositionX, $d.dmPositionY)
    }
}
Write-Host ''
Write-Host 'Pronto. Agora rode estender-iniciar.bat para enviar as telas ao Raspberry Pi.' -ForegroundColor Green
