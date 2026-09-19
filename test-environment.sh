#!/bin/bash
#################################################################################
# Script de Teste de Ambiente LazyCast
# Verifica se o ambiente está pronto para rodar o LazyCast
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "=========================================="
echo "  Teste de Ambiente LazyCast"
echo "=========================================="
echo ""

FAILED=0
PASSED=0

# Função para verificar comando
check_command() {
    local cmd=$1
    local name=$2
    local required=$3
    
    if command -v $cmd &> /dev/null; then
        echo "✓ $name encontrado"
        PASSED=$((PASSED + 1))
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "✗ $name NÃO encontrado (REQUERIDO)"
            FAILED=$((FAILED + 1))
            return 1
        else
            echo "⚠ $name não encontrado (opcional)"
            return 0
        fi
    fi
}

# Função para verificar arquivo
check_file() {
    local file=$1
    local name=$2
    local required=$3
    
    if [ -f "$file" ]; then
        echo "✓ $name encontrado"
        PASSED=$((PASSED + 1))
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "✗ $name NÃO encontrado (REQUERIDO)"
            FAILED=$((FAILED + 1))
            return 1
        else
            echo "⚠ $name não encontrado (opcional)"
            return 0
        fi
    fi
}

# Função para verificar módulo Python
check_python_module() {
    local module=$1
    local name=$2
    local required=$3
    
    if python3 -c "import $module" 2>/dev/null; then
        echo "✓ $name disponível"
        PASSED=$((PASSED + 1))
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "✗ $name NÃO disponível (REQUERIDO)"
            FAILED=$((FAILED + 1))
            return 1
        else
            echo "⚠ $name não disponível (opcional)"
            return 0
        fi
    fi
}

echo "=========================================="
echo "  Verificando Sistema Operacional"
echo "=========================================="
echo ""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Sistema: $NAME $VERSION"
    echo "Kernel: $(uname -r)"
    echo "Arquitetura: $(uname -m)"
    PASSED=$((PASSED + 1))
else
    echo "⚠ Não foi possível identificar o sistema operacional"
fi

echo ""
echo "=========================================="
echo "  Verificando Hardware"
echo "=========================================="
echo ""

# Verificar se é Raspberry Pi
if [ -f /proc/cpuinfo ]; then
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        echo "✓ Raspberry Pi detectado"
        PASSED=$((PASSED + 1))
        
        # Verificar modelo
        if grep -q "BCM2712" /proc/cpuinfo; then
            echo "✓ Raspberry Pi 5 detectado (ideal para dual display)"
        elif grep -q "BCM2711" /proc/cpuinfo; then
            echo "✓ Raspberry Pi 4 detectado"
        elif grep -q "BCM2835" /proc/cpuinfo; then
            echo "✓ Raspberry Pi 3/2 detectado"
        fi
    else
        echo "⚠ Não é um Raspberry Pi (pode ter funcionalidade limitada)"
    fi
else
    echo "⚠ /proc/cpuinfo não encontrado"
fi

# Verificar placas de rede
if command -v iw &> /dev/null; then
    if iw dev 2>/dev/null | grep -q "Interface"; then
        echo "✓ Interface WiFi disponível"
        PASSED=$((PASSED + 1))
    else
        echo "✗ Nenhuma interface WiFi encontrada"
        FAILED=$((FAILED + 1))
    fi
fi

echo ""
echo "=========================================="
echo "  Verificando Comandos Básicos"
echo "=========================================="
echo ""

check_command "python3" "Python 3" "required"
check_command "wpa_cli" "wpa_cli" "required"
check_command "ifconfig" "ifconfig" "required"
check_command "sudo" "sudo" "required"

echo ""
echo "=========================================="
echo "  Verificando Módulos Python"
echo "=========================================="
echo ""

check_python_module "socket" "socket" "required"
check_python_module "threading" "threading" "required"
check_python_module "subprocess" "subprocess" "required"
check_python_module "evdev" "evdev" "optional"

echo ""
echo "=========================================="
echo "  Verificando Arquivos LazyCast"
echo "=========================================="
echo ""

check_file "d2.py" "d2.py" "required"
check_file "d2-multi.py" "d2-multi.py" "optional"
check_file "all.sh" "all.sh" "required"
check_file "all-dual.sh" "all-dual.sh" "optional"
check_file "lazycast-config.conf" "lazycast-config.conf" "optional"

# Verificar scripts utilitários
check_file "clear_pairing.sh" "clear_pairing.sh" "optional"
check_file "player_health_check.sh" "player_health_check.sh" "optional"
check_file "check_dependencies.sh" "check_dependencies.sh" "optional"

echo ""
echo "=========================================="
echo "  Verificando Binários Compilados"
echo "=========================================="
echo ""

check_file "player/player.bin" "player.bin" "optional"
check_file "h264/h264.bin" "h264.bin" "optional"
check_file "control/control.bin" "control.bin" "optional"

echo ""
echo "=========================================="
echo "  Verificando Bibliotecas do Sistema"
echo "=========================================="
echo ""

# Verificar bibliotecas Raspberry Pi
if [ -d "/opt/vc/lib" ]; then
    echo "✓ Bibliotecas VideoCore encontradas"
    PASSED=$((PASSED + 1))
else
    echo "⚠ Bibliotecas VideoCore não encontradas (pode ser necessário em sistemas não-RPi)"
fi

if [ -d "/opt/vc/src/hello_pi" ]; then
    echo "✓ Bibliotecas hello_pi encontradas"
    PASSED=$((PASSED + 1))
else
    echo "⚠ Bibliotecas hello_pi não encontradas"
fi

echo ""
echo "=========================================="
echo "  Testando Sintaxe Python"
echo "=========================================="
echo ""

python_syntax_check() {
    local file=$1
    if python3 -m py_compile "$file" 2>/dev/null; then
        echo "✓ Sintaxe correta: $file"
        PASSED=$((PASSED + 1))
    else
        echo "✗ Erro de sintaxe: $file"
        FAILED=$((FAILED + 1))
    fi
}

if [ -f "d2.py" ]; then
    python_syntax_check "d2.py"
fi

if [ -f "d2-multi.py" ]; then
    python_syntax_check "d2-multi.py"
fi

if [ -f "project.py" ]; then
    python_syntax_check "project.py"
fi

echo ""
echo "=========================================="
echo "  Resumo do Teste"
echo "=========================================="
echo ""
echo "Testes passados: $PASSED"
echo "Testes falhados: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓ Todos os testes obrigatórios passaram!"
    echo "O ambiente parece estar pronto para rodar o LazyCast."
    exit 0
else
    echo "✗ Alguns testes falharam. Corrija os problemas antes de usar o LazyCast."
    exit 1
fi