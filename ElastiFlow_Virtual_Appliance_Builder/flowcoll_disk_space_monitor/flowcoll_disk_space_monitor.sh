#!/usr/bin/env bash
set -euo pipefail

THRESHOLD=80                            # % full at which we pause Flowcoll
LOG_FILE="/var/log/flowcoll_disk_space_monitor/flowcoll_disk_space_monitor.log"
GRACE_PERIOD=10                         # Seconds to wait for a clean stop before kill
SERVICE_NAME="flowcoll.service"         # Service to manage
DATA_PLATFORM=""
FLOW_CONFIG_PATH="/etc/elastiflow/flowcoll.yml"
disk_indices="" 
disk_used=""
disk_avail="" 
disk_total=""
disk_percent=""

log() {
  # log "message" [broadcast=true|false]
  local ts broadcast
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  broadcast=${2:-false}
  echo "${ts} $1" >> "${LOG_FILE}"
  [[ "${broadcast}" == "true" ]] && wall -n "${ts} $1" 2>/dev/null || true
}

detect_data_platform() {
  if systemctl is-active --quiet elasticsearch.service; then
    DATA_PLATFORM="elasticsearch.service"
  elif systemctl is-active --quiet opensearch.service; then
    DATA_PLATFORM="opensearch.service"
  else
    DATA_PLATFORM=""
    log "ERROR: Neither elasticsearch.service nor opensearch.service is running" >&2 "${should_broadcast}"
    exit 1
  fi
}


get_elasticsearch_info() {
  local password
  password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$password" ]]; then
    log "ERROR: Could not extract EF_OUTPUT_ELASTICSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2 true
    exit 1
  fi

  local output
  output=$(curl -s -f -u elastic:"$password" https://localhost:9200/_cat/allocation?v --insecure) || {
    log "ERROR: Flowcoll Disk Space Monitor failed to retrieve disk space usage" >&2 true
    exit 1
  }

  read -r disk_indices disk_used disk_avail disk_total disk_percent <<< $(echo "$output" | awk 'NR==2 {print $5, $6, $7, $8, $9}')
}

get_opensearch_info() {
  local password
  password=$(grep "^EF_OUTPUT_OPENSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$password" ]]; then
    echo "ERROR: Could not extract EF_OUTPUT_OPENSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2
    exit 1
  fi

  local output
  output=$(curl -s -f -u admin:"$password" https://localhost:9200/_cat/allocation?v --insecure) || {
    log "ERROR: Flowcoll Disk Space Monitor failed to retrieve disk space usage" >&2 true
    exit 1
  }

  read -r disk_indices disk_used disk_avail disk_total disk_percent <<< $(echo "$output" | awk 'NR==2 {print $2, $3, $4, $5, $6}')
}

get_disk_usage() {
  detect_data_platform

  if [[ "$DATA_PLATFORM" == "elasticsearch.service" ]]; then
    get_elasticsearch_info
  elif [[ "$DATA_PLATFORM" == "opensearch.service" ]]; then
    get_opensearch_info
  fi
}

stop_flowcoll_hard() {
  log "Above disk space usage threshold — stopping ${SERVICE_NAME}" true
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
  log "Free space OK. Below disk space usage threshold — starting ${SERVICE_NAME}"

  if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Starting ${SERVICE_NAME}"
    if systemctl start "${SERVICE_NAME}"; then
      log "${SERVICE_NAME} started successfully"
    else
      log "ERROR: Failed to start ${SERVICE_NAME}" true
    fi
  else
    log "${SERVICE_NAME} is already started"
  fi
}

handle_above_threshold() {
  log "Not enough free disk space - Above disk space usage threshold — stopping ${SERVICE_NAME}"

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Stopping ${SERVICE_NAME}" true
    stop_flowcoll_hard
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
      log "ERROR: ${SERVICE_NAME} is still running after stop attempt" true
    else
      log "${SERVICE_NAME} stopped successfully"
    fi
  else
    log "${SERVICE_NAME} is already stopped"
  fi
}

main() {
  get_disk_usage

  local should_broadcast
  should_broadcast=$([[ "${disk_percent}" -ge "${THRESHOLD}" ]] && echo true || echo false)

  log "${DATA_PLATFORM} disk space check: ${disk_percent}% used (${disk_used} GiB used / ${disk_indices} indices ${disk_avail} GiB free) (threshold ${THRESHOLD}%)" "${should_broadcast}"

  if [[ "${disk_percent}" -lt "${THRESHOLD}" ]]; then
    handle_below_threshold
  else
    handle_above_threshold
  fi
}

main "$@"
