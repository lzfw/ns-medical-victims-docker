#!/usr/bin/env bash

set -euo pipefail

# Before running this script, please make sure all required variables
# are set.

# Script exit code
BACKUP_EXIT=1
# Directory in which to perform the backup
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/ns-medical-victims-docker-cron}"
# Service name of the MariaDB/MySQL container to backup
CONTAINER_NAME_PATTERN="${CONTAINER_NAME_PATTERN:-ns-medical-victims-docker_db*}"
# Part that becomes the name of the dump file
DUMP_FILE_BASE_NAME="nmv"
# Whether to create backups
BACKUP_CREATE_BACKUPS="${BACKUP_CREATE_BACKUPS:-true}"
# Whether to delete old backups
DELETE_OLD_BACKUPS="${CONTAINER_NAME_PATTERN:-true}"
# Variable will be initialized with proper values later but must not be empty
TEMP_BACKUP_FILE=/tmp/does_no_exist

info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
exit_script() {
  if [ ${BACKUP_EXIT} -eq 0 ]; then
    info "backup successful"
  else
    info "backup error"
    [ -f "${TEMP_BACKUP_FILE}" ] && rm -f "${TEMP_BACKUP_FILE}"
    sleep 2
  fi
  exit "${BACKUP_EXIT}"
}

# Validate variables
[ -d "${BACKUP_DIR}" ] \
  || ( info "Backup directory '${BACKUP_DIR}' does not exist." ; exit_script )

CONTAINER_NAME=$(docker ps --filter "name=${CONTAINER_NAME_PATTERN}" --format "{{.Names}}") \
  || ( info "No container matching pattern ${CONTAINER_NAME_PATTERN} found." ; exit_script )

NUMBER_OF_CONTAINERS=$(echo "${CONTAINER_NAME}"|wc -w)
[ "$NUMBER_OF_CONTAINERS" -eq 1 ] \
  || ( info "There are ${NUMBER_OF_CONTAINERS} running. Expected 1." ; exit_script )

rm -rf "${BACKUP_DIR}/tmp.*"

if [ "${BACKUP_CREATE_BACKUPS}" == "true" ] ; then
  TEMP_BACKUP_FILE=$(mktemp -p "${BACKUP_DIR}")
  BACKUP_FILE_PATH="${BACKUP_DIR}/backup_${DUMP_FILE_BASE_NAME}_day_$(date +%F).sql.xz"
  WEEK_OF_MONTH="$((($(date +%-d)-1)/7+1))"
  MONTH_NAME="$(date +%B)"

  info "starting backup"

  #shellcheck disable=SC2016
  docker exec "${CONTAINER_NAME}" sh -c \
    'exec mysqldump --all-databases --all-databases --single-transaction --quick -uroot -p"$MYSQL_ROOT_PASSWORD"' > "${TEMP_BACKUP_FILE}" && MYSQLDUMP_RESULT="ok"

  # Result of last command
  if [ "$MYSQLDUMP_RESULT" == "ok" ] ; then
    # If the daily backup exists, can be compressed and hardlinked, the backup
    # is assumed to be successful
    xz "${TEMP_BACKUP_FILE}" && \
    mv "${TEMP_BACKUP_FILE}.xz" "${BACKUP_FILE_PATH}" && \
    ln -f "${BACKUP_FILE_PATH}" "${BACKUP_DIR}/latest_${DUMP_FILE_BASE_NAME}.sql.xz" && \
    BACKUP_EXIT=0

    # Refresh references to weekly and monthly backups
    ln -f "${BACKUP_FILE_PATH}" "${BACKUP_DIR}/backup_${DUMP_FILE_BASE_NAME}_week_${WEEK_OF_MONTH}.sql.xz" || \
BACKUP_EXIT=1
    ln -f "${BACKUP_FILE_PATH}" "${BACKUP_DIR}/backup_${DUMP_FILE_BASE_NAME}_month_${MONTH_NAME}.sql.xz" || \
BACKUP_EXIT=1
    # Delete old backups if configured that way
    if [ -f "${BACKUP_FILE_PATH}" ] && [ "${DELETE_OLD_BACKUPS}" == "true" ] ; then
      find "${BACKUP_DIR}" -name "backup_${DUMP_FILE_BASE_NAME}_day_*" -mtime +7 -delete
    fi
  fi
else
  BACKUP_EXIT=0
fi
exit ${BACKUP_EXIT}

