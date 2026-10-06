#!/usr/bin/env bash
# ==============================================================================
# Script: test_snmp.sh
# Objetivo: Testar a comunicação SNMP com a Brother DCP-T530DW (Páginas e Tinta)
# Uso: ./scripts/test_snmp.sh [IP_OPCIONAL]
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="$BASE_DIR/config/printer.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    CONFIG_FILE="$BASE_DIR/config/printer.conf.example"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Permite passar IP como argumento ou usar da configuração
TARGET_IP="${1:-${PRINTER_IP:-192.168.1.50}}"
COMMUNITY="${SNMP_COMMUNITY:-public}"
VERSION="${SNMP_VERSION:-2c}"
PAGE_OID="${OID_PAGE_COUNT:-1.3.6.1.2.1.43.10.2.1.4.1.1}"
BROTHER_MAINT_OID="${OID_BROTHER_MAINTENANCE:-1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0}"

echo "=========================================================="
echo "    TESTE DE DIAGNÓSTICO SNMP - BROTHER DCP-T530DW        "
echo "=========================================================="
echo "IP Alvo:       $TARGET_IP"
echo "Comunidade:    $COMMUNITY"
echo "Versão SNMP:   $VERSION"
echo "OID Páginas:   $PAGE_OID"
echo "OID Tinta:     $BROTHER_MAINT_OID"
echo "Arquivo Log:   ${LOG_FILE:-/opt/snmp-to-log/log/printer.log}"
echo "=========================================================="

if ! command -v snmpget >/dev/null 2>&1; then
    echo "[ERRO] snmpget não instalado! Execute: sudo apt install -y snmp"
    exit 1
fi

# 1. Identificação Geral
echo ""
echo "[1/4] Identificando dispositivo (sysDescr)..."
SYS_DESCR=$(snmpget -v"$VERSION" -c "$COMMUNITY" -t 3 -r 1 -Oqv "$TARGET_IP" 1.3.6.1.2.1.1.1.0 2>/dev/null || true)
if [[ -n "$SYS_DESCR" ]]; then
    echo "  -> Identificação: $SYS_DESCR"
else
    echo "  -> AVISO: Dispositivo não respondeu ao sysDescr. Verifique o IP e SNMP."
fi

# 2. Contador de Páginas
echo ""
echo "[2/4] Testando contador total de páginas (prtMarkerLifeCount)..."
PAGES=$(snmpget -v"$VERSION" -c "$COMMUNITY" -t 3 -r 1 -Oqv "$TARGET_IP" "$PAGE_OID" 2>/dev/null | tr -d '\r\n"' | xargs || true)
if [[ -n "$PAGES" && "$PAGES" =~ ^[0-9]+$ ]]; then
    echo "  -> SUCESSO: $PAGES páginas registradas na memória."
else
    echo "  -> FALHA: Não retornou valor numérico (retorno: '$PAGES')."
fi

# 3. Níveis de Tinta (Brother MIB)
echo ""
echo "[3/4] Testando leitura de tinta (OID Proprietário Brother)..."
RAW_HEX=$(snmpget -v"$VERSION" -c "$COMMUNITY" -t 3 -r 1 -Ox -Oqv "$TARGET_IP" "$BROTHER_MAINT_OID" 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]' || true)

parse_tag() {
    local stream="$1" tag="$2"
    if [[ "$stream" =~ ${tag}0104([0-9a-f]{8}) ]]; then
        local dec=$((16#${BASH_REMATCH[1]}))
        if (( dec > 100 && dec <= 10000 )); then
            echo $((dec / 100))
        elif (( dec >= 0 && dec <= 100 )); then
            echo "$dec"
        fi
    fi
}

if [[ -n "$RAW_HEX" ]]; then
    echo "  -> Resposta HEX recebida (${#RAW_HEX} caracteres)."
    BK=$(parse_tag "$RAW_HEX" "6f"); [[ -z "$BK" ]] && BK=$(parse_tag "$RAW_HEX" "81")
    CY=$(parse_tag "$RAW_HEX" "70"); [[ -z "$CY" ]] && CY=$(parse_tag "$RAW_HEX" "82")
    MG=$(parse_tag "$RAW_HEX" "71"); [[ -z "$MG" ]] && MG=$(parse_tag "$RAW_HEX" "83")
    YL=$(parse_tag "$RAW_HEX" "72"); [[ -z "$YL" ]] && YL=$(parse_tag "$RAW_HEX" "84")

    echo "  -> Preto (BK):    ${BK:-Não decodificado}%"
    echo "  -> Ciano (C):     ${CY:-Não decodificado}%"
    echo "  -> Magenta (M):   ${MG:-Não decodificado}%"
    echo "  -> Amarelo (Y):   ${YL:-Não decodificado}%"
else
    echo "  -> AVISO: OID proprietário Brother não retornou dados. Testando MIB padrão..."
    for i in 1 2 3 4; do
        val=$(snmpget -v"$VERSION" -c "$COMMUNITY" -t 2 -r 1 -Oqv "$TARGET_IP" "1.3.6.1.2.1.43.11.1.1.9.1.$i" 2>/dev/null || true)
        echo "     prtMarkerSuppliesLevel.$i = $val"
    done
fi

# 4. Permissões de escrita no arquivo de log
echo ""
echo "[4/4] Verificando diretório de log..."
LOG_DIR=$(dirname "${LOG_FILE:-/opt/snmp-to-log/log/printer.log}")
if [[ -w "$LOG_DIR" || ( ! -d "$LOG_DIR" && -w "$(dirname "$LOG_DIR")" ) ]]; then
    echo "  -> Diretório de log ($LOG_DIR) com permissão de escrita OK."
else
    echo "  -> ATENÇÃO: Verifique permissões de escrita em $LOG_DIR (use: sudo chown -R \$USER:\$USER /opt/snmp-to-log)."
fi

echo ""
echo "=========================================================="
echo "                  DIAGNÓSTICO CONCLUÍDO                   "
echo "=========================================================="
