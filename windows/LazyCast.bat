@echo off
rem Abre o programa LazyCast (lazycast_windows.py) sem janela de console.
rem Usa pythonw (nao o LazyCast.exe): o Controle de Inteligencia de Aplicativos do Windows 11 bloqueia
rem executaveis novos sem assinatura digital, mas o python.exe/pythonw.exe (assinado pela Python
rem Software Foundation) nao entra nesse bloqueio.
rem Precisa do Python 3 instalado (python.org) e, na primeira vez, das dependencias:
rem     pip install -r requirements.txt
cd /d "%~dp0"
where pythonw >nul 2>nul
if %errorlevel% neq 0 (
    echo Python nao encontrado. Instale em https://python.org (marque "Add to PATH") e rode de novo.
    pause
    exit /b 1
)
start "" pythonw lazycast_windows.py
