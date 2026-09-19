#!/bin/bash
#################################################################################
# Script de Teste de Sintaxe Bash
# Verifica se os scripts bash têm erros de sintaxe
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#################################################################################

echo "=========================================="
echo "  Teste de Sintaxe Bash"
echo "=========================================="
echo ""

FAILED=0
PASSED=0

# Função para testar sintaxe de arquivo bash
test_bash_syntax() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo "⚠ Arquivo não encontrado: $file"
        return 1
    fi
    
    if bash -n "$file" 2>/dev/null; then
        echo "✓ Sintaxe correta: $file"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo "✗ Erro de sintaxe: $file"
        bash -n "$file"  # Mostrar o erro
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "Testando scripts principais..."
test_bash_syntax "all.sh"
test_bash_syntax "all-dual.sh"
test_bash_syntax "install.sh"
test_bash_syntax "install-service.sh"
test_bash_syntax "setup-hdmi.sh"
test_bash_syntax "lazycast-background.sh"
test_bash_syntax "lazycast-status.sh"

echo ""
echo "Testando scripts utilitários..."
test_bash_syntax "clear_pairing.sh"
test_bash_syntax "player_health_check.sh"
test_bash_syntax "check_dependencies.sh"
test_bash_syntax "test-environment.sh"
test_bash_syntax "test-syntax.sh"
test_bash_syntax "make-executable.sh"

echo ""
echo "Testando sintaxe Python..."
for pyfile in d2.py d2-multi.py d2vlc.py d2win10debug.py newmice.py project.py scan.py; do
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
        echo "✓ Sintaxe correta: $pyfile"
        PASSED=$((PASSED + 1))
    else
        echo "✗ Erro de sintaxe: $pyfile"
        python3 -m py_compile "$pyfile"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Testando scripts legados..."
test_bash_syntax "vlcbased.sh"
test_bash_syntax "win10debug.sh"
test_bash_syntax "mice.sh"
test_bash_syntax "removep2p.sh"
test_bash_syntax "resetwpa.sh"

echo ""
echo "=========================================="
echo "  Resumo"
echo "=========================================="
echo ""
echo "Testes passados: $PASSED"
echo "Testes falhados: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓ Todos os scripts têm sintaxe correta!"
    exit 0
else
    echo "✗ Alguns scripts têm erros de sintaxe."
    exit 1
fi