# LazyCast para Windows - janela única para:
#   * ligar/desligar as telas virtuais e enviá-las ao Raspberry Pi pela rede (cabo ou Wi-Fi);
#   * conectar ao Pi por Miracast (o "Transmitir" do Windows).
# Usa os scripts desta pasta (configurar-telas-virtuais.ps1, estender-tela.ps1). Não precisa de administrador.
#
# Sem janela (para testes/automação): LazyCast-Windows.ps1 -Acao ligar|desligar|status|driver-status [-Telas 2] [-Pi IP[,IP]]
param([ValidateSet('', 'ligar', 'desligar', 'status', 'driver-status', 'baixar-driver')][string]$Acao = '', [int]$Telas = 2, [string]$Pi = '', [switch]$Remover, [string]$ZipLocal = '')

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$ipFile = Join-Path $pasta 'pi-ip.txt'
$nomeFile = Join-Path $pasta 'miracast-nome.txt'
$cfgVdd = 'C:\VirtualDisplayDriver\vdd_settings.xml'
. (Join-Path $pasta 'telas-virtuais.ps1')     # Get/Anexar/Desanexar-TelasVirtuais
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Ler($f) { if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { '' } }

# Roda um script desta pasta sem janela; devolve a saída (texto) e não segura processos filhos (ffmpeg).
function Rodar([string]$script, [string[]]$args2, [int]$timeoutSeg = 120) {
    $saida = [System.IO.Path]::GetTempFileName()
    # Cada argumento entre aspas: caminhos com espaço (pasta do usuário) não quebram o -File
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $pasta $script)) + $args2
    $linha = ($a | ForEach-Object { '"' + ("$_" -replace '"', '') + '"' }) -join ' '
    $p = Start-Process -FilePath $ps -ArgumentList $linha -WindowStyle Hidden -PassThru -RedirectStandardOutput $saida
    $fim = (Get-Date).AddSeconds($timeoutSeg)
    while (-not $p.HasExited -and (Get-Date) -lt $fim) {
        Start-Sleep -Milliseconds 200
        if ($script:form) { [System.Windows.Forms.Application]::DoEvents() }
    }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $script:ultimoExit = -1 }
    else { $script:ultimoExit = $p.ExitCode }
    $txt = (Get-Content $saida -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
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
    try {
        [xml]$x = Get-Content $cfgVdd -Raw
        $x.vdd_settings.monitors.count = "$n"
        $x.Save($cfgVdd)
        $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'MTTVirtualDisplayPipe', [System.IO.Pipes.PipeDirection]::InOut)
        $p.Connect(3000)
        $w = New-Object System.IO.StreamWriter($p); $w.AutoFlush = $true; $w.Write('RELOAD_DRIVER'); Start-Sleep -Milliseconds 800; $p.Dispose()
    } catch { return $false }
    return $true
}

function Ligar([int]$n, [string]$ip, [scriptblock]$log) {
    if (-not (Test-Path $cfgVdd)) { & $log 'Driver do monitor virtual não instalado (veja LEIA-ME.md, passo 2).'; return $false }
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}([,; ]+\d{1,3}(\.\d{1,3}){3})*$') { & $log 'IP inválido. Use, por exemplo, 192.168.0.43 (cabo e Wi-Fi separados por vírgula).'; return $false }
    $ip = ($ip -split '[,; ]+' | Where-Object { $_ }) -join ','
    Set-Content -Path $ipFile -Value $ip
    # 1) garante N monitores no driver (só recarrega o driver se faltarem: recarregar derruba os que existem)
    & $log "Preparando $n tela(s) virtual(is)..."
    if (@(Get-TelasVirtuais).Count -lt $n) {
        if (-not (Definir-Contagem $n)) { & $log 'Não consegui pedir os monitores ao driver.'; return $false }
        for ($i = 0; $i -lt 25 -and @(Get-TelasVirtuais).Count -lt $n; $i++) { Start-Sleep -Milliseconds 800; [System.Windows.Forms.Application]::DoEvents() }
    }
    if (@(Get-TelasVirtuais).Count -lt $n) { & $log 'O driver não criou os monitores. Reinicie o notebook e tente de novo.'; return $false }
    # 2) coloca na área de trabalho, 1920x1080 a 60 Hz
    $ativas = Anexar-TelasVirtuais $n
    if ($ativas -lt $n) { & $log 'As telas virtuais não entraram na área de trabalho. Tente Win+P > Estender.'; return $false }
    & $log "$ativas tela(s) virtual(is) ativa(s)."
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
        Start-Sleep 3
    } else {
        & $log 'Desativando as telas virtuais...'
        [void](Desanexar-TelasVirtuais)
    }
    & $log "Pronto. Telas extras ativas: $(Telas-Extras)."
}

# ---- driver do monitor virtual (Virtual Display Driver, projeto VirtualDrivers)
# Versão e hash fixos: o arquivo só é usado se o SHA-256 conferir com o publicado no GitHub. O instalador do driver
# (VDD Control.exe) é aberto com o pedido de administrador do Windows: quem aprova é você.
$drvUrl = 'https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/25.7.23/VDD.Control.25.7.23.zip'
$drvSha = 'a701f2272e9fcf382849b24f913c6dd07597b3b1116525f2e90182f019609154'
$drvPasta = Join-Path $env:LOCALAPPDATA 'LazyCast\driver'

function Driver-Instalado {
    if (Test-Path $cfgVdd) { return $true }
    [bool](Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -eq 'Virtual Display Driver' -and $_.Status -eq 'OK' })
}

# Baixa (ou usa -ZipLocal), confere o hash e extrai. Escreve o caminho do VDD Control.exe na última linha.
function Baixar-Driver([string]$zipLocal) {
    New-Item -ItemType Directory -Force -Path $drvPasta | Out-Null
    $zip = if ($zipLocal) { $zipLocal } else { Join-Path $drvPasta 'VDD.Control.25.7.23.zip' }
    if (-not $zipLocal -and -not (Test-Path $zip)) {
        Write-Host 'Baixando o driver do GitHub (68 MB)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $drvUrl -OutFile $zip -UseBasicParsing
    }
    $hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $drvSha) {
        if (-not $zipLocal) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        Write-Host "ERRO: o arquivo não confere com o hash esperado ($hash). Não foi usado."
        exit 2
    }
    Write-Host 'Arquivo verificado (SHA-256 confere).'
    $dest = Join-Path $drvPasta 'VDD'
    $exe = Join-Path $dest 'VDD Control.exe'
    # sempre extrai do zip verificado (um exe antigo/alterado na pasta nunca é reaproveitado)
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    if (-not (Test-Path $exe)) { Write-Host 'ERRO: VDD Control.exe não está no pacote.'; exit 3 }
    Write-Host $exe
}

function Instalar-Driver([scriptblock]$log) {
    if (Driver-Instalado) { & $log 'O driver já está instalado.'; return }
    $r = [System.Windows.Forms.MessageBox]::Show("Vou baixar o Virtual Display Driver (68 MB) do GitHub oficial do projeto VirtualDrivers, versão 25.7.23, e conferir o SHA-256 antes de abrir.`n`nEm seguida o Windows vai pedir permissão de administrador para o instalador do driver. Continuar?", 'Instalar driver', 'YesNo', 'Question')
    if ($r -ne 'Yes') { & $log 'Instalação cancelada.'; return }
    & $log 'Baixando e verificando o driver (pode levar alguns minutos)...'
    $o = Rodar 'LazyCast-Windows.ps1' @('-Acao', 'baixar-driver') 900
    $linhas = @($o -split "`r?`n" | Where-Object { $_ })
    $linhas | Select-Object -Last 2 | ForEach-Object { & $log $_ }
    $exe = Join-Path $drvPasta 'VDD\VDD Control.exe'          # caminho remontado aqui, não lido da saída do filho
    if ($script:ultimoExit -ne 0 -or -not (Test-Path -LiteralPath $exe)) { & $log 'Não foi possível preparar o driver.'; return }
    & $log 'Abrindo o instalador (confirme o pedido de administrador do Windows)...'
    try { Start-Process -FilePath $exe -Verb RunAs } catch { & $log 'Pedido de administrador negado ou cancelado.'; return }
    & $log 'No programa que abriu, instale o driver. Depois volte aqui: o estado do driver atualiza sozinho.'
}

# Remove o driver com o pnputil (administrador: o Windows pede a sua aprovação).
function Desinstalar-Driver([scriptblock]$log) {
    if (-not (Driver-Instalado)) { & $log 'O driver não está instalado.'; return }
    $r = [System.Windows.Forms.MessageBox]::Show("Desinstalar o Virtual Display Driver? As telas virtuais deixam de existir e o envio para o Pi é parado.`n`nO Windows vai pedir permissão de administrador.", 'Desinstalar driver', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { & $log 'Desinstalação cancelada.'; return }
    & $log 'Parando o envio...'
    [void](Rodar 'estender-tela.ps1' @('-Parar') 30)
    # acha o nome publicado (oemNN.inf) do pacote mttvdd.inf
    $blocos = (pnputil /enum-drivers | Out-String) -split '(\r?\n){2,}'
    $oem = $null
    foreach ($b in $blocos) { if ($b -match 'mttvdd\.inf' -and $b -match '(oem\d+\.inf)') { $oem = $Matches[1]; break } }
    if (-not $oem) { & $log 'Não encontrei o pacote do driver no Windows.'; return }
    & $log "Removendo $oem (confirme o pedido de administrador)..."
    try {
        $proc = Start-Process -FilePath "$env:WINDIR\System32\pnputil.exe" -ArgumentList '/delete-driver', $oem, '/uninstall', '/force' -Verb RunAs -Wait -PassThru -WindowStyle Hidden
    } catch { & $log 'Pedido de administrador negado ou cancelado.'; return }
    Start-Sleep 2
    & $log $(if (Driver-Instalado) { 'O driver ainda aparece instalado; reinicie o notebook ou use o VDD Control.' } else { 'Driver desinstalado.' })
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
        'driver-status' { if (Driver-Instalado) { 'Driver: instalado' } else { 'Driver: não instalado' } }
        'baixar-driver' { Baixar-Driver $ZipLocal }
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
$f.Text = 'LazyCast para Windows'; $f.StartPosition = 'CenterScreen'; $f.ClientSize = New-Object System.Drawing.Size(540, 600)
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$verde = [System.Drawing.Color]::FromArgb(30, 130, 60); $vermelho = [System.Drawing.Color]::FromArgb(190, 40, 40)
$cinza = [System.Drawing.Color]::FromArgb(100, 100, 100)

function Novo($tipo, $x, $y, $w, $h, $texto, $pai) {
    $c = New-Object "System.Windows.Forms.$tipo"
    $c.Location = New-Object System.Drawing.Point($x, $y); $c.Size = New-Object System.Drawing.Size($w, $h)
    if ($texto) { $c.Text = $texto }
    if (-not $pai) { $pai = $f }
    $pai.Controls.Add($c); return $c
}
function Grupo($titulo, $y, $h) {
    $g = Novo 'GroupBox' 16 $y 508 $h $titulo
    $g.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    return $g
}
function Normal($c, $tam = 9.5) { $c.Font = New-Object System.Drawing.Font('Segoe UI', $tam) }

# ---- 1. Driver (no topo: é o pré-requisito de tudo)
$g1 = Grupo '1. Driver do monitor virtual' 12 82
$lblDriver = Novo 'Label' 16 28 270 24 '' $g1
$lblDriver.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$lblDriverInfo = Novo 'Label' 16 54 300 20 '' $g1
Normal $lblDriverInfo 9; $lblDriverInfo.ForeColor = $cinza
$btnDriver = Novo 'Button' 330 26 166 34 'Instalar driver' $g1
$btnDesinst = Novo 'Button' 330 26 166 34 'Desinstalar driver' $g1
Normal $btnDriver; Normal $btnDesinst

# ---- 2. Tela estendida
$g2 = Grupo '2. Tela estendida para o Raspberry Pi (cabo ou Wi-Fi)' 104 178
$l = Novo 'Label' 16 30 300 20 'IP do Pi (cabo e/ou Wi-Fi, separados por vírgula)' $g2; Normal $l 9
$txtIp = Novo 'TextBox' 16 52 350 26 (Ler $ipFile) $g2; Normal $txtIp
$l = Novo 'Label' 384 30 110 20 'Telas virtuais' $g2; Normal $l 9
$cmbN = Novo 'ComboBox' 384 52 112 26 '' $g2; Normal $cmbN
$cmbN.DropDownStyle = 'DropDownList'; [void]$cmbN.Items.AddRange(@('1', '2')); $cmbN.SelectedItem = '2'
$btnLigar = Novo 'Button' 16 92 236 40 'Ligar tela virtual' $g2; Normal $btnLigar 10.5
$btnDesligar = Novo 'Button' 260 92 236 40 'Desligar' $g2; Normal $btnDesligar 10.5
$chkRem = Novo 'CheckBox' 16 144 480 22 'Ao desligar, remover também os monitores do driver (só voltam após reiniciar)' $g2
Normal $chkRem 8.5

# ---- 3. Miracast
$g3 = Grupo '3. Miracast (Transmitir do Windows)' 294 92
$l = Novo 'Label' 16 30 300 20 'Nome do receptor no Pi (ex.: LazyCast-Gecko)' $g3; Normal $l 9
$txtNome = Novo 'TextBox' 16 52 350 26 (Ler $nomeFile) $g3; Normal $txtNome
$btnMira = Novo 'Button' 384 48 112 34 'Conectar' $g3; Normal $btnMira

# ---- estado e log
$lblEstado = Novo 'Label' 16 396 508 22 ''
Normal $lblEstado 9; $lblEstado.ForeColor = $cinza
$txtLog = Novo 'TextBox' 16 422 508 162 ''
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)

$logFn = { param($m) $txtLog.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }
function Atualizar {
    $t = Transmitindo; $e = Telas-Extras
    $di = Driver-Instalado
    if ($di) {
        $lblDriver.Text = '● Driver já instalado'; $lblDriver.ForeColor = $verde
        $lblDriverInfo.Text = 'Virtual Display Driver (VirtualDrivers)'
    } else {
        $lblDriver.Text = '● Driver não instalado'; $lblDriver.ForeColor = $vermelho
        $lblDriverInfo.Text = 'Necessário para criar as telas virtuais.'
    }
    $btnDriver.Visible = -not $di       # já instalado: esconde "Instalar" e mostra "Desinstalar"
    $btnDesinst.Visible = $di
    $btnLigar.Enabled = $di
    $btnDesligar.Enabled = ($t -gt 0 -or $e -gt 0)
    $lblEstado.Text = "Enviando: $t fluxo(s)   |   Telas virtuais ativas: $e"
}
function Ocupado($sim) {
    $f.UseWaitCursor = $sim
    foreach ($b in @($btnLigar, $btnDesligar, $btnMira, $btnDriver, $btnDesinst)) { $b.Enabled = -not $sim }
    if (-not $sim) { Atualizar }
    [System.Windows.Forms.Application]::DoEvents()
}

$btnLigar.Add_Click({
    Ocupado $true
    try { [void](Ligar ([int]$cmbN.SelectedItem) $txtIp.Text.Trim() $logFn) } finally { Ocupado $false }
})
$btnDesligar.Add_Click({ Ocupado $true; try { Desligar $logFn $chkRem.Checked } finally { Ocupado $false } })
$btnDriver.Add_Click({ Ocupado $true; try { Instalar-Driver $logFn } finally { Ocupado $false } })
$btnDesinst.Add_Click({ Ocupado $true; try { Desinstalar-Driver $logFn } finally { Ocupado $false } })
$btnMira.Add_Click({ Miracast $txtNome.Text.Trim() $logFn })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000; $timer.Add_Tick({ if (-not $f.UseWaitCursor) { Atualizar } }); $timer.Start()
Atualizar
[void]$f.ShowDialog()
