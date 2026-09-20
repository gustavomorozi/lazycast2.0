@echo off
REM LazyCast - estende a tela do Windows para o Raspberry Pi (Tela 1 e Tela 2).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0estender-tela.ps1" -Iniciar %*
echo.
pause
