#!/usr/bin/env bash
set -euo pipefail

PARTITION="/"           # filesystem to watch
THRESHOLD=80            # % full at which we pause Flowcoll
LOG_FILE="/var/log/flowcoll_disk_space_monitor.log"
GRACE_PERIOD=10         # seconds to wait for a clean stop before kill

log() {
  # log "message" [broadcast=true|false]
  local ts broadcast
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  broadcast=${2:-false}
  echo "${ts} $1" >> "${LOG_FILE}"
  [[ "${broadcast}" == "true" ]] && wall -n "${ts} $1" 2>/dev/null || true
}

stop_flowcoll_hard() {
  log "Above threshold — stopping flowcoll.service" true
  systemctl stop flowcoll.service || true

  # Wait up to GRACE_PERIOD seconds for graceful shutdown
  for (( i=0; i<GRACE_PERIOD; i++ )); do
    if ! systemctl is-active --quiet flowcoll.service; then
      log "flowcoll.service stopped gracefully" true
      return
    fi
    sleep 1
  done

  # Still running → kill it hard
  log "flowcoll.service did not stop within ${GRACE_PERIOD}s — killing now" true
  systemctl kill flowcoll.service || true
}

# ─── Gather disk stats ────────────────────────────────────────────────────────
usage_pct=$(df --output=pcent "$PARTITION" | tail -1 | tr -dc '0-9')
read used_gib free_gib < <(
  df -BG --output=used,avail "$PARTITION" |
  tail -1 | awk '{ sub(/G/,"",$1); sub(/G/,"",$2); print $1, $2 }'
)

log "Disk check: ${usage_pct}% used (${used_gib} GiB used / ${free_gib} GiB free) on ${PARTITION} (threshold ${THRESHOLD}%)" \
    $([[ "${usage_pct}" -ge "${THRESHOLD}" ]] && echo true || echo false)
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${usage_pct}" -lt "${THRESHOLD}" ]]; then
  # Below threshold – keep Flowcoll up
  if ! systemctl is-enabled --quiet flowcoll.service; then
    log "Below threshold — enabling flowcoll.service"
    systemctl enable flowcoll.service
  fi
  if ! systemctl is-active --quiet flowcoll.service; then
    log "Below threshold — starting flowcoll.service"
    systemctl start flowcoll.service
  fi
else
  # Above threshold – shut Flowcoll down, killing if needed
  if systemctl is-enabled --quiet flowcoll.service; then
    log "Above threshold — disabling flowcoll.service" true
    systemctl disable flowcoll.service
  fi
  if systemctl is-active --quiet flowcoll.service; then
    stop_flowcoll_hard
  fi
fi
