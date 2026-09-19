@echo off
REM LazyCast - para a transmissao das telas para o Raspberry Pi.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0estender-tela.ps1" -Parar
echo.
pause
