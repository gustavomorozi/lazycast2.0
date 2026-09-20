# LazyCast (Windows) - liga e desliga as telas do Virtual Display Driver na área de trabalho, sem DisplaySwitch.
# O DisplaySwitch (Win+P) nem sempre anexa/solta os monitores virtuais; aqui usamos ChangeDisplaySettingsEx,
# que grava a posição/modo de cada monitor virtual e aplica de uma vez.
#
# Uso (dot-source):  . .\telas-virtuais.ps1 ; Anexar-TelasVirtuais 2 ; Desanexar-TelasVirtuais
# Uso direto:        telas-virtuais.ps1 -Anexar 2 | -Desanexar | -Listar

param([int]$Anexar = 0, [switch]$Desanexar, [switch]$Listar)

if (-not ('LcTV' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class LcTV {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct DISPLAY_DEVICE { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString; public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey; }
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
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE d, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string dev, IntPtr dm, IntPtr hwnd, int flags, IntPtr lp);
  // O PowerShell converte $null em "" ao chamar a API; estes atalhos passam null de verdade.
  public static bool EnumTop(uint i, ref DISPLAY_DEVICE d) { return EnumDisplayDevices(null, i, ref d, 0); }
  public static int Aplicar() { return ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero); }
}
"@
}

# Monitores do Virtual Display Driver: @{ Nome = '\\.\DISPLAYn'; Anexado = $true/$false }
function Get-TelasVirtuais {
    $r = @()
    for ($i = 0; $i -lt 60; $i++) {
        $d = New-Object LcTV+DISPLAY_DEVICE; $d.cb = [Runtime.InteropServices.Marshal]::SizeOf($d)
        if (-not [LcTV]::EnumTop([uint32]$i, [ref]$d)) { break }
        if ($d.DeviceString -eq 'Virtual Display Driver') { $r += [pscustomobject]@{ Nome = $d.DeviceName; Anexado = [bool]($d.StateFlags -band 1) } }
    }
    return $r
}

function Novo-DevMode {
    $dm = New-Object LcTV+DEVMODE
    $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($dm)
    return $dm
}

# Solta da área de trabalho (o monitor continua existindo no driver). Devolve quantas soltou.
function Desanexar-TelasVirtuais {
    $n = 0
    foreach ($t in (Get-TelasVirtuais | Where-Object { $_.Anexado })) {
        $dm = Novo-DevMode
        $dm.dmFields = 0x20 -bor 0x80000 -bor 0x100000          # posição | largura | altura (0x0 = desanexar)
        $dm.dmPelsWidth = 0; $dm.dmPelsHeight = 0
        if ([LcTV]::ChangeDisplaySettingsEx($t.Nome, [ref]$dm, [IntPtr]::Zero, (0x1 -bor 0x10000000), [IntPtr]::Zero) -eq 0) { $n++ }
    }
    if ($n) { [void][LcTV]::Aplicar() }
    Start-Sleep 2
    return $n
}

# Anexa até $max monitores virtuais, lado a lado à direita da última tela, em 1920x1080@60.
function Anexar-TelasVirtuais([int]$max = 2, [int]$w = 1920, [int]$h = 1080, [int]$hz = 60) {
    $lista = @(Get-TelasVirtuais)
    $ativas = @($lista | Where-Object { $_.Anexado }).Count
    if ($ativas -ge $max) { return $ativas }
    # posição X: logo depois da tela mais à direita já anexada
    $x = 0
    for ($i = 0; $i -lt 60; $i++) {
        $d = New-Object LcTV+DISPLAY_DEVICE; $d.cb = [Runtime.InteropServices.Marshal]::SizeOf($d)
        if (-not [LcTV]::EnumTop([uint32]$i, [ref]$d)) { break }
        if ($d.StateFlags -band 1) {
            $m = Novo-DevMode
            if ([LcTV]::EnumDisplaySettings($d.DeviceName, -1, [ref]$m)) { $x = [Math]::Max($x, $m.dmPositionX + $m.dmPelsWidth) }
        }
    }
    foreach ($t in ($lista | Where-Object { -not $_.Anexado } | Select-Object -First ($max - $ativas))) {
        $dm = Novo-DevMode
        $dm.dmFields = 0x20 -bor 0x80000 -bor 0x100000 -bor 0x400000
        $dm.dmPositionX = $x; $dm.dmPositionY = 0; $dm.dmPelsWidth = $w; $dm.dmPelsHeight = $h; $dm.dmDisplayFrequency = $hz
        $rc = [LcTV]::ChangeDisplaySettingsEx($t.Nome, [ref]$dm, [IntPtr]::Zero, (0x1 -bor 0x10000000), [IntPtr]::Zero)
        if ($rc -ne 0) { Write-Host "Aviso: $($t.Nome) não aceitou ${w}x${h}@${hz} (código $rc)." }
        $x += $w
    }
    [void][LcTV]::Aplicar()
    Start-Sleep 3
    return @(Get-TelasVirtuais | Where-Object { $_.Anexado }).Count
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Listar) { Get-TelasVirtuais | ForEach-Object { '{0} anexado={1}' -f $_.Nome, $_.Anexado } }
    elseif ($Desanexar) { 'soltas: ' + (Desanexar-TelasVirtuais) }
    elseif ($Anexar -gt 0) { 'anexadas: ' + (Anexar-TelasVirtuais $Anexar) }
}
