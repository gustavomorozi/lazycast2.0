# Gera o windows\LazyCast.exe a partir de lazycast_windows.py (so precisa ser usado por quem for
# mexer no codigo; quem so vai USAR o programa nao precisa disso, LazyCast.exe ja vem pronto no repositorio).
#
# Uso: build.ps1
param()
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $pasta

python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r requirements.txt pyinstaller

python -m PyInstaller --noconfirm --onefile --windowed --name LazyCast --icon lazycast.ico `
    --distpath . --workpath build --specpath build lazycast_windows.py

Write-Host "Pronto: $pasta\LazyCast.exe"
