#!/usr/bin/env bash
# ==============================================================================
# Script: setup_cron.sh
# Objetivo: Gerenciar a entrada do cron para execução a cada 5 minutos
# Uso:
#   ./scripts/setup_cron.sh           # Instala a tarefa no crontab
#   ./scripts/setup_cron.sh --remove  # Remove a tarefa do crontab
#   ./scripts/setup_cron.sh --status  # Exibe status da tarefa no cron
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/printer_log.sh"
CRON_SCHEDULE="*/5 * * * *"
CRON_ENTRY="$CRON_SCHEDULE $TARGET_SCRIPT >/dev/null 2>&1"
CRON_TAG="# printer_log_cron_job"

ACTION="${1:---install}"

# Obter crontab atual sem falhar se estiver vazio
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

case "$ACTION" in
    --remove|-r)
        echo "Removendo agendamento do cron..."
        if echo "$CURRENT_CRON" | grep -F "$TARGET_SCRIPT" >/dev/null 2>&1; then
            NEW_CRON=$(echo "$CURRENT_CRON" | grep -v -F "$TARGET_SCRIPT" | grep -v -F "$CRON_TAG")
            if [[ -z "$NEW_CRON" ]]; then
                crontab -r 2>/dev/null || true
            else
                echo "$NEW_CRON" | crontab -
            fi
            echo "Agendamento removido com sucesso!"
        else
            echo "Nenhuma entrada encontrada para este script no cron."
        fi
        ;;

    --status|-s)
        echo "Verificando agendamento no crontab:"
        if echo "$CURRENT_CRON" | grep -F "$TARGET_SCRIPT" >/dev/null 2>&1; then
            echo "[ATIVO] Entrada encontrada:"
            echo "$CURRENT_CRON" | grep -F "$TARGET_SCRIPT"
        else
            echo "[INATIVO] Nenhuma entrada encontrada para este script."
        fi
        ;;

    --install|-i|*)
        echo "Configurando agendamento a cada 5 minutos no crontab..."
        if echo "$CURRENT_CRON" | grep -F "$TARGET_SCRIPT" >/dev/null 2>&1; then
            echo "[AVISO] O script já está agendado no crontab!"
            echo "Linha atual:"
            echo "$CURRENT_CRON" | grep -F "$TARGET_SCRIPT"
            exit 0
        fi

        # Adiciona a entrada preservando as existentes
        (
            if [[ -n "$CURRENT_CRON" ]]; then
                echo "$CURRENT_CRON"
            fi
            echo "$CRON_ENTRY $CRON_TAG"
        ) | crontab -

        echo "[SUCESSO] Tarefa agendada com sucesso!"
        echo "Entrada adicionada: $CRON_ENTRY"
        echo "A coleta será executada a cada 5 minutos."
        ;;
esac
