#!/usr/bin/env bash
# ==============================================================================
# Script: printer_log.sh
# Objetivo: Coletar contador de páginas e níveis de tinta (%) via SNMP
# Modelo alvo: Brother DCP-T530DW (e compatíveis com MIB padrão)
# Ideal para execução periódica via cron (ex: a cada hora).
# ==============================================================================

set -uo pipefail

# Diretório base do script e do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carregar arquivo de configuração se existir
CONFIG_FILE="$BASE_DIR/config/printer.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    CONFIG_FILE="$BASE_DIR/config/printer.conf.example"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Valores padrão de fallback
PRINTER_IP="${PRINTER_IP:-192.168.1.50}"
SNMP_COMMUNITY="${SNMP_COMMUNITY:-public}"
SNMP_VERSION="${SNMP_VERSION:-2c}"
SNMP_TIMEOUT="${SNMP_TIMEOUT:-3}"
SNMP_RETRIES="${SNMP_RETRIES:-2}"
OID_PAGE_COUNT="${OID_PAGE_COUNT:-1.3.6.1.2.1.43.10.2.1.4.1.1}"
OID_BROTHER_MAINTENANCE="${OID_BROTHER_MAINTENANCE:-1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0}"
LOG_INK_LEVELS="${LOG_INK_LEVELS:-true}"
LOG_FILE="${LOG_FILE:-/opt/snmp-to-log/log/printer.log}"
LOG_OFFLINE_EVENTS="${LOG_OFFLINE_EVENTS:-false}"

# Validação do utilitário snmpget
if ! command -v snmpget >/dev/null 2>&1; then
    echo "[ERRO] snmpget não encontrado. Instale com: sudo apt update && sudo apt install -y snmp" >&2
    exit 1
fi

# Garantir que a pasta de logs exista
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# ==============================================================================
# Função: Extrair percentual de consumível da string HEX da Brother
# Padrão Brother: [TAG] 01 04 [4 BYTES DE VALOR]
# ==============================================================================
parse_brother_tag() {
    local hex_stream="$1"
    local tag="$2"
    local hex_val=""
    local dec_val=0

    # Busca padrão da tag + 0104 + 8 caracteres hexadecimais
    if [[ "$hex_stream" =~ ${tag}0104([0-9a-f]{8}) ]]; then
        hex_val="${BASH_REMATCH[1]}"
        dec_val=$((16#$hex_val))

        # Se valor vier na escala 0-10000 (ex: 10000 = 100%), converte para %
        if (( dec_val > 100 && dec_val <= 10000 )); then
            echo $((dec_val / 100))
        elif (( dec_val >= 0 && dec_val <= 100 )); then
            echo "$dec_val"
        fi
    fi
}

# ==============================================================================
# Função: Obter níveis de tinta (BK, C, M, Y)
# ==============================================================================
get_ink_levels() {
    local bk="" cy="" mg="" yl=""

    # 1. Tentativa via OID proprietário Brother (brInfoMaintenance)
    local raw_hex
    raw_hex=$(snmpget -v"${SNMP_VERSION}" \
                      -c "${SNMP_COMMUNITY}" \
                      -t "${SNMP_TIMEOUT}" \
                      -r "${SNMP_RETRIES}" \
                      -Ox -Oqv "${PRINTER_IP}" "${OID_BROTHER_MAINTENANCE}" 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]' || true)

    if [[ -n "$raw_hex" ]]; then
        # Tags conhecidas da Brother: 6f/81 (Preto), 70/82 (Ciano), 71/83 (Magenta), 72/84 (Amarelo)
        bk=$(parse_brother_tag "$raw_hex" "6f")
        [[ -z "$bk" ]] && bk=$(parse_brother_tag "$raw_hex" "81")

        cy=$(parse_brother_tag "$raw_hex" "70")
        [[ -z "$cy" ]] && cy=$(parse_brother_tag "$raw_hex" "82")

        mg=$(parse_brother_tag "$raw_hex" "71")
        [[ -z "$mg" ]] && mg=$(parse_brother_tag "$raw_hex" "83")

        yl=$(parse_brother_tag "$raw_hex" "72")
        [[ -z "$yl" ]] && yl=$(parse_brother_tag "$raw_hex" "84")
    fi

    # 2. Fallback: Tentativa via MIB padrão RFC 3805 (prtMarkerSuppliesTable)
    if [[ -z "$bk" && -z "$cy" && -z "$mg" && -z "$yl" ]]; then
        for idx in 1 2 3 4; do
            local cur max
            cur=$(snmpget -v"${SNMP_VERSION}" -c "${SNMP_COMMUNITY}" -t 2 -r 1 -Oqv "${PRINTER_IP}" "1.3.6.1.2.1.43.11.1.1.9.1.$idx" 2>/dev/null | tr -d '\r\n"' | xargs || true)
            max=$(snmpget -v"${SNMP_VERSION}" -c "${SNMP_COMMUNITY}" -t 2 -r 1 -Oqv "${PRINTER_IP}" "1.3.6.1.2.1.43.11.1.1.8.1.$idx" 2>/dev/null | tr -d '\r\n"' | xargs || true)

            if [[ "$cur" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && "$max" -gt 0 ]]; then
                local pct=$(( (cur * 100) / max ))
                case $idx in
                    1) bk="$pct" ;;
                    2) cy="$pct" ;;
                    3) mg="$pct" ;;
                    4) yl="$pct" ;;
                esac
            fi
        done
    fi

    # Se ao menos uma cor foi detectada, formata o retorno
    if [[ -n "$bk" || -n "$cy" || -n "$mg" || -n "$yl" ]]; then
        echo "Tinta: BK: ${bk:-N/A}% | C: ${cy:-N/A}% | M: ${mg:-N/A}% | Y: ${yl:-N/A}%"
    fi
}

# ==============================================================================
# Execução Principal: Consulta de Páginas
# ==============================================================================
PAGES=$(snmpget -v"${SNMP_VERSION}" \
                -c "${SNMP_COMMUNITY}" \
                -t "${SNMP_TIMEOUT}" \
                -r "${SNMP_RETRIES}" \
                -Oqv "${PRINTER_IP}" "${OID_PAGE_COUNT}" 2>/dev/null | tr -d '\r\n"' | xargs || true)

if [[ -n "$PAGES" && "$PAGES" =~ ^[0-9]+$ ]]; then
    LOG_LINE="$TIMESTAMP | Paginas: $PAGES"

    # Se configurado para coletar tinta, consulta os níveis
    if [[ "$LOG_INK_LEVELS" == "true" ]]; then
        INK_INFO=$(get_ink_levels)
        if [[ -n "$INK_INFO" ]]; then
            LOG_LINE="$LOG_LINE | $INK_INFO"
        fi
    fi

    echo "$LOG_LINE" >> "$LOG_FILE"

    if [ -t 1 ]; then
        echo "[$TIMESTAMP] Sucesso: Gravado em $LOG_FILE"
        echo "  -> $LOG_LINE"
    fi
else
    if [[ "$LOG_OFFLINE_EVENTS" == "true" ]]; then
        echo "$TIMESTAMP | AVISO: Impressora inacessivel ou sem resposta ($PRINTER_IP)" >> "$LOG_FILE"
    fi
    if [ -t 1 ]; then
        echo "[$TIMESTAMP] Falha: Não foi possível obter contagem da impressora $PRINTER_IP" >&2
    fi
    exit 2
fi
