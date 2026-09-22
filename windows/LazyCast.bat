@echo off
rem Abre o programa LazyCast para Windows (tela virtual para o Pi e Miracast).
rem sem -WindowStyle Hidden: o proprio script esconde o console (GetConsoleWindow); os dois juntos impediam a janela de abrir
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0LazyCast-Windows.ps1"
