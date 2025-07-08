#!/usr/bin/env bash
set -euo pipefail

PARTITION="/"                           # Filesystem to watch
THRESHOLD=80                            # % full at which we pause Flowcoll
LOG_FILE="/var/log/flowcoll_disk_space_monitor/flowcoll_disk_space_monitor.log"
GRACE_PERIOD=10                         # Seconds to wait for a clean stop before kill
SERVICE_NAME="flowcoll.service"         # Service to manage
DATA_PLATFORM=""
FLOW_CONFIG_PATH="/etc/elastiflow/flowcoll.yml"
USAGE_PERCENT=""



get_disk_usage(){

if [[ "$DATA_PLATFORM" == "elasticsearch.service" ]]; then
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$elastic_password" ]]; then
    echo "ERROR: Could not extract EF_OUTPUT_ELASTICSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2
    exit 1
  fi

  # Attempt to get the disk usage percent
  USAGE_PERCENT=$(curl -s -f -u elastic:"$elastic_password" https://localhost:9200/_cat/allocation?v --insecure | awk 'NR==2 {print $9}')

  # Check if curl or awk failed or if output is empty/non-numeric
  if [[ $? -ne 0 || -z "$USAGE_PERCENT" || ! "$USAGE_PERCENT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Failed to retrieve disk usage percent from Elasticsearch." >&2
    exit 1
  fi

  echo "Disk usage is $USAGE_PERCENT%"

elif [[ "$DATA_PLATFORM" == "opensearch.service" ]]; then

  # Extract opensearch password from flowcoll config
  opensearch_password=$(grep "^EF_OUTPUT_OPENSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$opensearch_password" ]]; then
    echo "ERROR: Could not extract EF_OUTPUT_OPENSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2
    exit 1
  fi

  # Attempt to get the disk usage percent
  USAGE_PERCENT=$(curl -s -f -u admin:"$opensearch_password" https://localhost:9200/_cat/allocation?v --insecure | awk 'NR==2 {print $6}')

  # Check if curl or awk failed or if output is empty/non-numeric
  if [[ $? -ne 0 || -z "$USAGE_PERCENT" || ! "$USAGE_PERCENT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Failed to retrieve disk usage percent from OpenSearch." >&2
    exit 1
  fi

  echo "Disk usage is $USAGE_PERCENT%"
fi

}



log() {
  # log "message" [broadcast=true|false]
  local ts broadcast
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  broadcast=${2:-false}
  echo "${ts} $1" >> "${LOG_FILE}"
  [[ "${broadcast}" == "true" ]] && wall -n "${ts} $1" 2>/dev/null || true
}

detect_data_platform() {
  if systemctl list-unit-files | grep -q '^elasticsearch\.service'; then
    DATA_PLATFORM="elasticsearch.service"
  elif systemctl list-unit-files | grep -q '^opensearch\.service'; then
    DATA_PLATFORM="opensearch.service"
  else
    DATA_PLATFORM=""
    echo "ERROR: Neither elasticsearch.service nor opensearch.service is defined"
    exit 1
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

log "You have enough free disk space. Below disk space usage threshold — enabling and starting ${SERVICE_NAME}"

if ! systemctl is-enabled --quiet "${SERVICE_NAME}"; then
  log "Enabling ${SERVICE_NAME}"
  if systemctl enable "${SERVICE_NAME}"; then
    log "${SERVICE_NAME} enabled successfully"
  else
    log "ERROR: Failed to enable ${SERVICE_NAME}" true
  fi
else
  log "${SERVICE_NAME} is already enabled"
fi

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

log "Not enough free disk space - Above disk space usage threshold — disabling and stopping ${SERVICE_NAME}"

if systemctl is-enabled --quiet "${SERVICE_NAME}"; then
  log "Disabling ${SERVICE_NAME}" true
  if systemctl disable "${SERVICE_NAME}"; then
    log "${SERVICE_NAME} disabled successfully"
  else
    log "ERROR: Failed to disable ${SERVICE_NAME}" true
  fi
else
  log "${SERVICE_NAME} is already disabled"
fi

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

  detect_data_platform
  
  get_disk_usage
  
  local should_broadcast
  
  should_broadcast=$([[ "${USAGE_PERCENT}" -ge "${THRESHOLD}" ]] && echo true || echo false)

  log "Disk space check: ${USAGE_PERCENT}% used (${used_gib} GiB used / ${free_gib} GiB free) on ${PARTITION} (threshold ${THRESHOLD}%)" "${should_broadcast}"

  if [[ "${USAGE_PERCENT}" -lt "${THRESHOLD}" ]]; then
    handle_below_threshold
  else
    handle_above_threshold
  fi
}

main "$@"
