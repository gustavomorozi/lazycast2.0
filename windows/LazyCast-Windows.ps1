# LazyCast para Windows - janela única para:
#   * ligar/desligar as telas virtuais e enviá-las ao Raspberry Pi pela rede (cabo ou Wi-Fi);
#   * conectar ao Pi por Miracast (o "Transmitir" do Windows).
# Usa os scripts desta pasta (configurar-telas-virtuais.ps1, estender-tela.ps1). Não precisa de administrador.
#
# Sem janela (para testes/automação): LazyCast-Windows.ps1 -Acao ligar|desligar|status [-Telas 2] [-Pi IP[,IP]]
param([ValidateSet('', 'ligar', 'desligar', 'status')][string]$Acao = '', [int]$Telas = 2, [string]$Pi = '', [switch]$Remover)

$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$ipFile = Join-Path $pasta 'pi-ip.txt'
$nomeFile = Join-Path $pasta 'miracast-nome.txt'
$cfgVdd = 'C:\VirtualDisplayDriver\vdd_settings.xml'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Ler($f) { if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { '' } }

# Roda um script desta pasta sem janela; devolve a saída (texto) e não segura processos filhos (ffmpeg).
function Rodar([string]$script, [string[]]$args2, [int]$timeoutSeg = 120) {
    $saida = [System.IO.Path]::GetTempFileName()
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $pasta $script)) + $args2
    $p = Start-Process -FilePath $ps -ArgumentList $a -WindowStyle Hidden -PassThru -RedirectStandardOutput $saida
    $fim = (Get-Date).AddSeconds($timeoutSeg)
    while (-not $p.HasExited -and (Get-Date) -lt $fim) {
        Start-Sleep -Milliseconds 200
        if ($script:form) { [System.Windows.Forms.Application]::DoEvents() }
    }
    $txt = (Get-Content $saida -Raw -ErrorAction SilentlyContinue)
    Remove-Item $saida -Force -ErrorAction SilentlyContinue
    return "$txt".Trim()
}

function Transmitindo {
    $pids = Join-Path $pasta 'estender.pids'
    if (-not (Test-Path $pids)) { return 0 }
    @(Get-Content $pids | Where-Object { $_ -match '^\d+$' } | Where-Object { Get-Process -Id ([int]$_) -ErrorAction SilentlyContinue }).Count
}

function Telas-Extras {
    Add-Type -AssemblyName System.Windows.Forms
    @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary }).Count
}

function Definir-Contagem([int]$n) {
    if (-not (Test-Path $cfgVdd)) { return $false }
    [xml]$x = Get-Content $cfgVdd -Raw
    $x.vdd_settings.monitors.count = "$n"
    $x.Save($cfgVdd)
    try {
        $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'MTTVirtualDisplayPipe', [System.IO.Pipes.PipeDirection]::InOut)
        $p.Connect(3000)
        $w = New-Object System.IO.StreamWriter($p); $w.AutoFlush = $true; $w.Write('RELOAD_DRIVER'); Start-Sleep -Milliseconds 800; $p.Dispose()
    } catch { return $false }
    return $true
}

function Ligar([int]$n, [string]$ip, [scriptblock]$log) {
    if (-not (Test-Path $cfgVdd)) { & $log 'Driver do monitor virtual não instalado (veja LEIA-ME.md, passo 2).'; return $false }
    if (-not $ip) { & $log 'Informe o IP do Raspberry Pi.'; return $false }
    Set-Content -Path $ipFile -Value $ip
    & $log "Criando $n tela(s) virtual(is)..."
    $o = Rodar 'configurar-telas-virtuais.ps1' @('-Telas', "$n") 90
    $o -split "`r?`n" | Where-Object { $_ -match 'ok|Pronto|Nenhuma|não' } | ForEach-Object { & $log $_ }
    if ((Telas-Extras) -lt $n) {
        Start-Process "$env:WINDIR\System32\DisplaySwitch.exe" -ArgumentList '/extend' -Wait; Start-Sleep 3     # reativa telas desativadas
    }
    if ((Telas-Extras) -lt $n) { & $log 'As telas virtuais não apareceram. Reinicie o notebook e tente de novo.'; return $false }
    & $log "Enviando ao Pi ($ip)..."
    $o = Rodar 'estender-tela.ps1' @('-Iniciar', '-Pi', $ip, '-Telas', "$n") 40
    $o -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 3 | ForEach-Object { & $log $_ }
    Start-Sleep 2
    $t = Transmitindo
    & $log $(if ($t -ge 1) { "Pronto: $t tela(s) sendo enviada(s) ao Pi." } else { 'O envio não iniciou (veja estender-tela1.log).' })
    return ($t -ge 1)
}

# Padrão: só para o envio e desativa as telas (Win+P > Somente tela do PC); elas voltam com "Ligar".
# -Remover: zera os monitores do driver. O driver não recria os monitores até reiniciar o notebook.
function Desligar([scriptblock]$log, [bool]$remover = $false) {
    & $log 'Parando o envio...'
    [void](Rodar 'estender-tela.ps1' @('-Parar') 30)
    if ($remover) {
        & $log 'Removendo os monitores virtuais do driver (para voltar, reinicie o notebook)...'
        if (-not (Definir-Contagem 0)) { & $log 'Não consegui recarregar o driver; reinicie o notebook para remover as telas.' }
    } else {
        & $log 'Desativando as telas virtuais...'
    }
    Start-Process "$env:WINDIR\System32\DisplaySwitch.exe" -ArgumentList '/internal' -Wait
    Start-Sleep 3
    & $log "Pronto. Telas extras ativas: $(Telas-Extras)."
}

function Miracast([string]$nome, [scriptblock]$log) {
    if ($nome) { Set-Content -Path $nomeFile -Value $nome }
    & $log $(if ($nome) { "Abrindo o painel de transmitir: escolha '$nome' na lista." } else { 'Abrindo o painel de transmitir: escolha o receptor LazyCast na lista.' })
    Start-Process 'ms-settings-connectabledevices:devicediscovery'
}

# ---------------------------------------------------------------- modo sem janela
if ($Acao) {
    $log = { param($m) Write-Host $m }
    $ip = if ($Pi) { $Pi } else { Ler $ipFile }
    switch ($Acao) {
        'ligar'    { if (Ligar $Telas $ip $log) { exit 0 } else { exit 1 } }
        'desligar' { Desligar $log ([bool]$Remover) }
        'status'   { "Enviando: $(Transmitindo) fluxo(s); telas virtuais ativas: $(Telas-Extras)" }
    }
    exit 0
}

# ---------------------------------------------------------------- janela
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:form = New-Object System.Windows.Forms.Form
$f = $script:form
$f.Text = 'LazyCast para Windows'; $f.StartPosition = 'CenterScreen'; $f.Size = New-Object System.Drawing.Size(520, 470)
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)

function Novo($tipo, $x, $y, $w, $h, $texto) {
    $c = New-Object "System.Windows.Forms.$tipo"
    $c.Location = New-Object System.Drawing.Point($x, $y); $c.Size = New-Object System.Drawing.Size($w, $h)
    if ($texto) { $c.Text = $texto }
    $f.Controls.Add($c); return $c
}

[void](Novo 'Label' 20 15 470 22 'Tela estendida para o Raspberry Pi (cabo ou Wi-Fi)')
$f.Controls[0].Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
[void](Novo 'Label' 20 48 200 22 'IP do Pi (cabo, Wi-Fi):')
$txtIp = Novo 'TextBox' 20 72 300 26 (Ler $ipFile)
[void](Novo 'Label' 335 48 120 22 'Telas virtuais:')
$cmbN = Novo 'ComboBox' 335 72 60 26 ''
$cmbN.DropDownStyle = 'DropDownList'; [void]$cmbN.Items.AddRange(@('1', '2')); $cmbN.SelectedItem = '2'
$chkRem = Novo 'CheckBox' 20 156 470 22 'Ao desligar, remover também os monitores do driver (só voltam após reiniciar)'
$chkRem.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$btnLigar = Novo 'Button' 20 112 230 40 'Ligar tela virtual'
$btnDesligar = Novo 'Button' 260 112 230 40 'Desligar e remover'

$lbl2 = Novo 'Label' 20 185 470 22 'Miracast (Transmitir do Windows, como Win+K)'
$lbl2.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
[void](Novo 'Label' 20 215 200 22 'Nome do receptor no Pi:')
$txtNome = Novo 'TextBox' 20 239 300 26 (Ler $nomeFile)
$btnMira = Novo 'Button' 335 235 155 34 'Conectar por Miracast'

$lblEstado = Novo 'Label' 20 285 470 24 ''
$txtLog = Novo 'TextBox' 20 315 470 100 ''
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.BackColor = [System.Drawing.Color]::White

$logFn = { param($m) $txtLog.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }
function Atualizar {
    $t = Transmitindo; $e = Telas-Extras
    $lblEstado.Text = "Enviando: $t fluxo(s)   |   Telas virtuais ativas: $e"
    $btnDesligar.Enabled = ($t -gt 0 -or $e -gt 0)
}
function Ocupado($sim) {
    $f.UseWaitCursor = $sim
    foreach ($b in @($btnLigar, $btnDesligar, $btnMira)) { $b.Enabled = -not $sim }
    if (-not $sim) { Atualizar }
    [System.Windows.Forms.Application]::DoEvents()
}

$btnLigar.Add_Click({
    Ocupado $true
    try { [void](Ligar ([int]$cmbN.SelectedItem) $txtIp.Text.Trim() $logFn) } finally { Ocupado $false }
})
$btnDesligar.Add_Click({ Ocupado $true; try { Desligar $logFn $chkRem.Checked } finally { Ocupado $false } })
$btnMira.Add_Click({ Miracast $txtNome.Text.Trim() $logFn })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000; $timer.Add_Tick({ if (-not $f.UseWaitCursor) { Atualizar } }); $timer.Start()
Atualizar
[void]$f.ShowDialog()
