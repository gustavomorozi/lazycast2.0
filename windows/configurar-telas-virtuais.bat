@echo off
REM LazyCast - liga o driver de monitor virtual e ajusta as telas (2 telas 1920x1080@60). Rode 1 vez.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar-telas-virtuais.ps1" %*
echo.
pause
