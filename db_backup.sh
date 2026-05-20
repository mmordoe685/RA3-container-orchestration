#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
ENV_FILE="${SCRIPT_DIR}/.env"
CONTAINER_NAME="ra3-db"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=7

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { err "$*"; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker no esta instalado o no esta en el PATH."

[ -f "${ENV_FILE}" ] || die "No se encuentra el fichero .env en ${ENV_FILE}."

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

: "${MYSQL_DATABASE:?La variable MYSQL_DATABASE no esta definida en .env}"
: "${MYSQL_ROOT_PASSWORD:?La variable MYSQL_ROOT_PASSWORD no esta definida en .env}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    die "El contenedor '${CONTAINER_NAME}' no esta en ejecucion. Lanza 'docker compose up -d' primero."
fi

mkdir -p "${BACKUP_DIR}"
BACKUP_FILE="${BACKUP_DIR}/ra3_backup_${TIMESTAMP}.sql"

log "Iniciando backup de la base '${MYSQL_DATABASE}' desde el contenedor '${CONTAINER_NAME}'..."

if ! docker exec -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" -i "${CONTAINER_NAME}" \
        mysqldump \
            --single-transaction \
            --routines \
            --triggers \
            --quick \
            --no-tablespaces \
            -uroot \
            "${MYSQL_DATABASE}" > "${BACKUP_FILE}"; then
    err "Fallo el mysqldump. Se elimina el fichero parcial."
    rm -f "${BACKUP_FILE}"
    exit 1
fi

if [ ! -s "${BACKUP_FILE}" ]; then
    err "El backup generado esta vacio."
    rm -f "${BACKUP_FILE}"
    exit 1
fi

BACKUP_SIZE="$(du -h "${BACKUP_FILE}" | cut -f1)"
log "Backup completado: ${BACKUP_FILE} (${BACKUP_SIZE})"

log "Aplicando retencion de ${RETENTION_DAYS} dias..."
DELETED=$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'ra3_backup_*.sql' -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
log "Backups antiguos eliminados: ${DELETED}"

exit 0
