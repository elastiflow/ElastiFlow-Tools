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
USAGE_INDICES=""
USAGE_GB=""
DISK_FREE_GB=""
DISK_TOTAL_GB=""

get_elasticsearch_info(){


  # Extract elasticsearch password from flowcoll config
  password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$password" ]]; then
    echo "ERROR: Could not extract EF_OUTPUT_ELASTICSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2
    exit 1
  fi

  # Attempt to get the disk usage percent
  output=$(curl -s -f -u admin:"$password" https://localhost:9200/_cat/allocation?v --insecure) || {
    echo "ERROR: Failed to retrieve allocation data" >&2
    exit 1
  }

  read -r USAGE_INDICES USAGE_GB DISK_FREE_GB DISK_TOTAL_GB USAGE_PERCENT <<< $(echo "$output" | awk 'NR==2 {print $2, $3, $4, $5, $6}')
  echo "Disk usage is $USAGE_PERCENT%"

}

get_opensearch_info(){

 # Extract opensearch password from flowcoll config
  password=$(grep "^EF_OUTPUT_OPENSEARCH_PASSWORD: '" "$FLOW_CONFIG_PATH" | awk -F"'" '{print $2}')

  if [[ -z "$password" ]]; then
    echo "ERROR: Could not extract EF_OUTPUT_OPENSEARCH_PASSWORD from $FLOW_CONFIG_PATH" >&2
    exit 1
  fi

  # Attempt to get the disk usage percent
  output=$(curl -s -f -u admin:"$password" https://localhost:9200/_cat/allocation?v --insecure) || {
    echo "ERROR: Failed to retrieve allocation data" >&2
    exit 1
  }

  read -r USAGE_INDICES USAGE_GB DISK_FREE_GB DISK_TOTAL_GB USAGE_PERCENT <<< $(echo "$output" | awk 'NR==2 {print $2, $3, $4, $5, $6}')
  echo "Disk usage is $USAGE_PERCENT%"
fi
}



get_disk_usage(){

detect_data_platform

if [[ "$DATA_PLATFORM" == "elasticsearch.service" ]]; then
  get_elasticsearch_info
  
elif [[ "$DATA_PLATFORM" == "opensearch.service" ]]; then
  get_opensearch_info
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
  if systemctl list-unit-files | grep 'elasticsearch.service'; then
    DATA_PLATFORM="elasticsearch.service"
  elif systemctl list-unit-files | grep 'opensearch.service'; then
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
 
  get_disk_usage
  
  local should_broadcast
  
  should_broadcast=$([[ "${USAGE_PERCENT}" -ge "${THRESHOLD}" ]] && echo true || echo false)

  log "Disk space check: ${USAGE_PERCENT}% used (${USAGE_GB} GiB used / ${DISK_FREE_GB} GiB free) (threshold ${THRESHOLD}%)" "${should_broadcast}"

  if [[ "${USAGE_PERCENT}" -lt "${THRESHOLD}" ]]; then
    handle_below_threshold
  else
    handle_above_threshold
  fi
}

main "$@"
