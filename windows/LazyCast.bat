@echo off
rem Abre o programa LazyCast para Windows (tela virtual para o Pi e Miracast).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0LazyCast-Windows.ps1"
