#!/usr/bin/env bash
set -euo pipefail

PARTITION="/"                     # Filesystem to watch
THRESHOLD=80                      # % full at which we pause Flowcoll
LOG_FILE="/var/log/flowcoll_disk_space_monitor.log"
GRACE_PERIOD=10                   # Seconds to wait for a clean stop before kill
SERVICE_NAME="flowcoll.service"  # Service to manage

log() {
  # log "message" [broadcast=true|false]
  local ts broadcast
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  broadcast=${2:-false}
  echo "${ts} $1" >> "${LOG_FILE}"
  [[ "${broadcast}" == "true" ]] && wall -n "${ts} $1" 2>/dev/null || true
}

service_exists() {
  systemctl list-units --full --all | grep "${SERVICE_NAME}"
}

gather_disk_stats() {
  usage_pct=$(df --output=pcent "$PARTITION" | tail -1 | tr -dc '0-9')
  read used_gib free_gib < <(
    df -BG --output=used,avail "$PARTITION" |
    tail -1 | awk '{ sub(/G/,"",$1); sub(/G/,"",$2); print $1, $2 }'
  )
}

stop_flowcoll_hard() {
  log "Above threshold — stopping ${SERVICE_NAME}" true
  systemctl stop "${SERVICE_NAME}" || true

  for (( i=0; i<GRACE_PERIOD; i++ )); do
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
      log "${SERVICE_NAME} stopped gracefully" true
      return
    fi
    sleep 1
  done

  log "${SERVICE_NAME} did not stop within ${GRACE_PERIOD}s — killing now" true
  systemctl kill "${SERVICE_NAME}" || true
}

handle_below_threshold() {
  if ! systemctl is-enabled --quiet "${SERVICE_NAME}"; then
    log "Below threshold — enabling ${SERVICE_NAME}"
    systemctl enable "${SERVICE_NAME}"
  fi
  if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Below threshold — starting ${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
  fi
}

handle_above_threshold() {
  if systemctl is-enabled --quiet "${SERVICE_NAME}"; then
    log "Above threshold — disabling ${SERVICE_NAME}" true
    systemctl disable "${SERVICE_NAME}"
  fi
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    stop_flowcoll_hard
  fi
}

main() {
  if ! service_exists; then
    log "${SERVICE_NAME} not found on system — exiting."
    exit 0
  fi

  gather_disk_stats

  local should_broadcast
  should_broadcast=$([[ "${usage_pct}" -ge "${THRESHOLD}" ]] && echo true || echo false)

  log "Disk check: ${usage_pct}% used (${used_gib} GiB used / ${free_gib} GiB free) on ${PARTITION} (threshold ${THRESHOLD}%)" "${should_broadcast}"

  if [[ "${usage_pct}" -lt "${THRESHOLD}" ]]; then
    handle_below_threshold
  else
    handle_above_threshold
  fi
}

main "$@"
