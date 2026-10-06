#!/usr/bin/env bash
# ==============================================================================
# Script: install.sh
# Objetivo: Instalar dependências e preparar ambiente em /opt/snmp-to-log
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="/opt/snmp-to-log"

echo "=========================================================="
echo "    INSTALAÇÃO - COLETOR DE LOG SNMP DE IMPRESSORA        "
echo "=========================================================="

# 1. Ajustar permissões de execução dos scripts locais
echo "[1/4] Ajustando permissões de execução dos scripts..."
chmod +x "$SCRIPT_DIR"/scripts/*.sh
chmod +x "$SCRIPT_DIR"/install.sh 2>/dev/null || true

# 2. Instalar pacote snmp se não presente
echo "[2/4] Verificando utilitário snmpget..."
if ! command -v snmpget >/dev/null 2>&1; then
    echo "Instalando pacote 'snmp' via apt..."
    sudo apt update -y
    sudo apt install -y snmp
else
    echo "Pacote 'snmp' já está instalado."
fi

# 3. Preparar diretório padrão em /opt/snmp-to-log se necessário
echo "[3/4] Preparando diretórios em /opt/snmp-to-log..."
if [[ "$SCRIPT_DIR" != "$TARGET_DIR" ]]; then
    echo "Deseja copiar o projeto para o caminho padrão $TARGET_DIR? [s/N]"
    read -r -t 10 response || response="n"
    if [[ "$response" =~ ^[sSyY]$ ]]; then
        sudo mkdir -p "$TARGET_DIR"
        sudo cp -r "$SCRIPT_DIR"/* "$TARGET_DIR"/
        sudo chown -R "$USER":"$USER" "$TARGET_DIR"
        echo "Projeto sincronizado em $TARGET_DIR."
    fi
fi

# Garantir criação da pasta de logs com permissões do usuário
sudo mkdir -p "$TARGET_DIR/log"
sudo chown -R "$USER":"$USER" "$TARGET_DIR"

# 4. Criar arquivo de configuração inicial se não existir
echo "[4/4] Verificando configuração local..."
if [[ ! -f "$SCRIPT_DIR/config/printer.conf" ]]; then
    cp "$SCRIPT_DIR/config/printer.conf.example" "$SCRIPT_DIR/config/printer.conf"
    echo "Arquivo 'config/printer.conf' criado."
fi

echo "=========================================================="
echo "                 INSTALAÇÃO CONCLUÍDA!                    "
echo "=========================================================="
echo "Próximos passos:"
echo "1. Edite o IP da impressora em config/printer.conf:"
echo "   nano config/printer.conf"
echo ""
echo "2. Execute o diagnóstico completo (páginas e tinta):"
echo "   ./scripts/test_snmp.sh"
echo ""
echo "3. Faça um teste de execução manual:"
echo "   ./scripts/printer_log.sh"
echo ""
echo "4. Ative o agendamento horário no cron:"
echo "   ./scripts/setup_cron.sh"
echo "=========================================================="
