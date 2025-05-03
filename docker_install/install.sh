#!/bin/bash

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define Global Variables
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"


# Function to check if the user is root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

check_flow_blocker_health() {
  local service="flow_blocker.service"

  if systemctl is-active --quiet "$service"; then
    return 0
  else
    return 1
  fi
}


install_flow_blocker() {
  local script_path="/usr/local/bin/flow_blocker.sh"
  local service_path="/etc/systemd/system/flow_blocker.service"
  local log_file="/var/log/flow_blocker.log"
  local logrotate_conf="/etc/logrotate.d/flow_blocker"

  echo "Creating flow_blocker script at $script_path..."

  sudo tee "$script_path" > /dev/null << 'EOF'
#!/bin/bash

threshold_block=20
threshold_unblock=25
interval=30
restart_policy="unless-stopped"

es_url="https://localhost:9200"
es_auth="-u elastic:$ELASTIC_PASSWORD"
es_curl_opts="-k -s"

log_file="/var/log/flow_blocker.log"

log() {
  echo "[$(date)] $*" | tee -a "$log_file"
}

log "Starting flow_blocker (monitoring Docker and flowcoll.service)..."

while true; do
  disk_json=$(curl $es_curl_opts $es_auth "$es_url/_nodes/stats/fs?filter_path=nodes.*.fs.total")

  available_bytes=$(echo "$disk_json" | jq '[.nodes[].fs.total.available_in_bytes] | min')
  total_bytes=$(echo "$disk_json" | jq '[.nodes[].fs.total.total_in_bytes] | max')

  if [[ -z "$available_bytes" || -z "$total_bytes" || "$available_bytes" == "null" || "$total_bytes" == "null" ]]; then
    log "❌ Failed to get valid disk space metrics from Elasticsearch."
    sleep "$interval"
    continue
  fi

  free_pct=$(echo "scale=2; 100 * $available_bytes / $total_bytes" | bc -l)
  log "Free disk space (via ES): ${free_pct}%"

  # --- Docker container ---
  container_info=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep "flow-collector" | head -n 1)
  container_id=$(echo "$container_info" | awk '{print $1}')
  container_name=$(echo "$container_info" | awk '{print $2}')
  if [ -n "$container_id" ]; then
    is_running=$(docker inspect -f '{{.State.Running}}' "$container_id")
  else
    is_running="unknown"
  fi

  if (( $(echo "$free_pct <= $threshold_block" | bc -l) )); then
    if [ "$is_running" = "true" ]; then
      log "❌ Low disk space. Stopping Docker container: $container_name"
      docker update --restart=no "$container_id"
      docker stop "$container_id"
      wall <<EOFMSG
⚠️  DOCKER STOPPED: Elasticsearch reports low disk space on $(hostname).
Container '$container_name' has been stopped and disabled.
EOFMSG
    fi

    if systemctl is-active --quiet flowcoll.service; then
      log "❌ Low disk space. Stopping systemd service: flowcoll.service"
      systemctl stop flowcoll.service
      systemctl disable flowcoll.service
      wall <<EOFMSG
⚠️  SERVICE STOPPED: Elasticsearch reports low disk space on $(hostname).
Systemd service 'flowcoll.service' has been stopped and disabled.
EOFMSG
    fi
  fi

  if (( $(echo "$free_pct > $threshold_unblock" | bc -l) )); then
    if [ "$is_running" = "false" ]; then
      log "✅ Disk recovered. Starting Docker container: $container_name"
      docker update --restart=$restart_policy "$container_id"
      docker start "$container_id"
      wall <<EOFMSG
✅ DOCKER RESTARTED: Disk space recovered on $(hostname).
Container '$container_name' has been restarted.
EOFMSG
    fi

    if systemctl is-enabled --quiet flowcoll.service && ! systemctl is-active --quiet flowcoll.service; then
      log "✅ Disk recovered. Starting systemd service: flowcoll.service"
      systemctl enable flowcoll.service
      systemctl start flowcoll.service
      wall <<EOFMSG
✅ SERVICE RESTARTED: Disk space recovered on $(hostname).
Systemd service 'flowcoll.service' has been re-enabled and started.
EOFMSG
    fi
  fi

  sleep "$interval"
done
EOF

  sudo chmod +x "$script_path"
  echo "✅ Script written to $script_path"

  echo "Creating systemd service at $service_path..."

  sudo tee "$service_path" > /dev/null << EOF
[Unit]
Description=Flow Collector Disk Monitor
After=network.target
Requires=

[Service]
Type=simple
ExecStart=$script_path
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  echo "Creating logrotate configuration at $logrotate_conf..."

  sudo tee "$logrotate_conf" > /dev/null << EOF
/var/log/flow_blocker.log {
  daily
  rotate 30
  compress
  missingok
  notifempty
  create 640 root adm
}
EOF

  echo "Reloading systemd and starting flow_blocker..."

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable --now flow_blocker.service

  echo "✅ flow_blocker.service is active and logs will be rotated (30 days retained)"
}



remove_docker_snap() {
  # Check if the Docker Snap is present
  if snap list | grep docker; then
    echo "Docker Snap is installed. Removing with --purge..."
    sudo snap remove --purge docker
    echo "Docker Snap has been removed."
  else
    echo "Docker Snap is not installed; nothing to remove."
  fi
}

check_for_ubuntu() {
  if [ -f /etc/os-release ]; then
    # Source the OS release info
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
      echo "Error: This script requires Ubuntu, but detected '$ID'. Exiting."
      exit 1
    fi
  else
    echo "Error: /etc/os-release not found. Cannot verify OS. Exiting."
    exit 1
  fi
}

check_rw(){
# Check if /var/lib is mounted read-only
if findmnt -n -o OPTIONS /var/lib | grep -qw ro; then
  echo "Error: /var/lib is mounted read-only. Exiting."
  exit 1
fi
}

check_all_containers_up() {
  local check_interval=1
  local required_time=10
  local elapsed_time=0
  declare -A container_status_summary

  local GREEN='\033[0;32m'
  local RED='\033[0;31m'
  local NC='\033[0m'

  local containers=($(docker ps --format "{{.ID}}:{{.Names}}"))

  if [ ${#containers[@]} -eq 0 ]; then
    echo "No running containers found."
    return 1
  fi

  echo "Checking if all Docker containers remain 'Up' for at least $required_time seconds..."

  for container in "${containers[@]}"; do
    local container_name=$(echo "$container" | cut -d':' -f2)
    container_status_summary["$container_name"]="stable"
  done

  while [ $elapsed_time -lt $required_time ]; do
    for container in "${containers[@]}"; do
      local container_id=$(echo "$container" | cut -d':' -f1)
      local container_name=$(echo "$container" | cut -d':' -f2)

      local status=$(docker ps --filter "id=$container_id" --format "{{.Status}}")

      if [[ "$status" != Up* ]]; then
        container_status_summary["$container_name"]="not stable"
      fi
    done

    sleep $check_interval
    elapsed_time=$((elapsed_time + check_interval))
  done

  echo -e "\nSummary of Docker container statuses after $required_time seconds:"
  local all_stable=true
  for container_name in "${!container_status_summary[@]}"; do
    if [ "${container_status_summary[$container_name]}" == "stable" ]; then
      print_message "Container '$container_name' is stable." "$GREEN"
    else
      print_message "Container '$container_name' is not stable." "$RED"
      all_stable=false
    fi
  done

  if [ "$all_stable" = true ]; then
    return 0
  else
    return 1
  fi
}



edit_env_file() {
  local env_file="$INSTALL_DIR/.env"  # Change this path to your actual .env file location
  local answer

  while true; do
    echo "Would you like to edit the .env file before proceeding? This is not required if you are using 64GB of RAM. Otherwise, adjustments need to be made to this file. (y/n) [Default: no in 20 seconds]"

    # Read user input with a timeout of 20 seconds
    read -t 20 -p "Enter your choice (y/n): " answer

    # If the user doesn't respond in time
    if [ $? -ne 0 ]; then
      echo "No response. Proceeding after 20 seconds."
      return 0  # Proceed without editing
    fi

    # Check the user's response
    case "$answer" in
      [yY]|[yY][eE][sS])
        echo "Opening .env file for editing..."
        nano "$env_file"  # Open the .env file with nano
        return 0  # Exit after editing
        ;;
      [nN]|[nN][oO]|"")
        echo "Proceeding without editing the .env file."
        return 0  # Exit the function without editing
        ;;
      *)
        echo "Invalid input. Please answer y/yes or n/no."
        ;;
    esac
  done
}


check_system_health() {
  printf "\n\n*********************************"
  printf "*********************************\n"

  check_all_containers_up
  local containers_ok=$?

  check_elastic_ready
  local elastic_ok=$?

  check_kibana_ready
  local kibana_ok=$?

  check_elastiflow_flow_open_ports
  local ports_ok=$?

  check_elastiflow_livez
  local livez_ok=$?

  check_flow_blocker_health
  local blocker_ok=$?

  if [ "$INSTALL_FLOWCOLL" = "1" ]; then
    get_dashboard_status "ElastiFlow (flow): Overview"
    local dashboard_flow_ok=$?
  else
    local dashboard_flow_ok=0
  fi

  if [ "$INSTALL_SNMPCOLLTRAP" = "1" ]; then
    get_dashboard_status "ElastiFlow (telemetry): Overview"
    local dashboard_telemetry_ok=$?
    get_dashboard_status "ElastiFlow (log): Log Records"
    local dashboard_log_ok=$?
  else
    local dashboard_telemetry_ok=0
    local dashboard_log_ok=0
  fi

  # Final result check
  if [ "$containers_ok" -eq 0 ] &&
     [ "$elastic_ok" -eq 0 ] &&
     [ "$kibana_ok" -eq 0 ] &&
     [ "$ports_ok" -eq 0 ] &&
     [ "$livez_ok" -eq 0 ] &&
     [ "$blocker_ok" -eq 0 ] &&
     [ "$dashboard_flow_ok" -eq 0 ] &&
     [ "$dashboard_telemetry_ok" -eq 0 ] &&
     [ "$dashboard_log_ok" -eq 0 ]; then
    echo "✅ All system health checks passed."
    return 0
  else
    echo "❌ One or more system health checks failed."
    return 1
  fi
}


get_dashboard_status(){
 get_dashboard_url "$1"
    if [ "$dashboard_url" == "Dashboard not found" ]; then
      print_message "Dashboard $1: URL: $dashboard_url" "$RED"
      return 1
    else
      print_message "Dashboard $1: URL: $dashboard_url" "$GREEN"
      return 0
    fi
}


get_host_ip() {
  INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(docker|lo)' | head -n 1)
  if [ -z "$INTERFACE" ]; then
    echo "No suitable network interface found."
    return 1
  else
    ip_address=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}' | cut -d/ -f1)
    if [ -z "$ip_address" ]; then
      echo "No IP address found for interface $INTERFACE."
      return 1
    else
      return 0
    fi
  fi
}


get_dashboard_url() {
  get_host_ip
  local kibana_url="https://$ip_address:5601"
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  local response=$(curl -k -s -u "elastic:$ELASTIC_PASSWORD" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
  local dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  if [ -z "$dashboard_id" ]; then
    dashboard_url="Dashboard not found"
  else
    dashboard_url="$kibana_url/app/kibana#/dashboard/$dashboard_id"
  fi
}


 check_elastiflow_readyz(){
   response=$(curl -s http://localhost:8080/readyz)
      if echo "$response" | grep -q "200"; then
        print_message "ElastiFlow Flow Collector is $response" "$GREEN"
      else
        print_message "ElastiFlow Flow Collector Readyz: $response" "$RED"
      fi
  }


check_elastiflow_livez() {
  response=$(curl -s http://localhost:8080/livez)
  if echo "$response" | grep -q "200"; then
    print_message "ElastiFlow Flow Collector is $response" "$GREEN"
    return 0
  else
    print_message "ElastiFlow Flow Collector Livez: $response" "$RED"
    return 1
  fi
}


check_elastiflow_flow_open_ports() {
  local env_file="$INSTALL_DIR/elastiflow_flow_compose.yml"

  local port_list=$(grep -v '^#' "$env_file" | grep 'EF_FLOW_SERVER_UDP_PORT' | cut -d ':' -f2 | tr -d ' ')

  if [ -z "$port_list" ]; then
    echo "No ports found in the EF_FLOW_SERVER_UDP_PORT variable."
    return 1
  fi

  local found_open=false
  IFS=',' read -ra ports <<< "$port_list"
  for port in "${ports[@]}"; do
    if netstat -tuln | grep -q ":$port"; then
      print_message "ElastiFlow Flow Collector port $port is open." "$GREEN"
      found_open=true
    else
      print_message "ElastiFlow Flow Collector is not ready for flow on $port." "$RED"
    fi
  done

  if [ "$found_open" = true ]; then
    return 0
  else
    return 1
  fi
}



check_elastic_ready(){
  curl_result=$(curl -s -k -u "elastic:$ELASTIC_PASSWORD" https://localhost:9200)
     search_text='"tagline" : "You Know, for Search"'
     if echo "$curl_result" | grep -q "$search_text"; then
       print_message "Elastic is ready. Used authenticated curl." "$GREEN"
       return 0
     else
       print_message "Elastic is not ready." "$RED"
       echo "$curl_result"
       return 1
     fi
}


check_kibana_ready(){
  response=$(curl -k -s -X GET "https://localhost:5601/api/status")
    
    if [[ $response == *'"status":{"overall":{"level":"available"}}'* ]]; then
        print_message "Kibana is ready. Used curl." "$GREEN"
        return 0
    else
        print_message "Kibana is not ready" "$RED"
        echo "$response"
        return 1
    fi
}


# Function to ask the user if they want to deploy ElastiFlow Flow Collector
ask_deploy_elastiflow_flow() {
  
  if [ "$FULL_AUTO" -eq 1 ]; then
    echo "FULL_AUTO is set to 1. Skipping prompt and deploying ElastiFlow Flow Collector."
    deploy_elastiflow_flow
    return 0
  fi  
  
  while true; do
    read -p "Do you want to deploy ElastiFlow Flow Collector? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        deploy_elastiflow_flow
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying ElastiFlow."
        return 0  # Exit the function but not the script
        ;;
      *)
        echo "Please answer y/yes or n/no."
        ;;
    esac
  done
}


# Function to ask the user if they want to deploy ElastiFlow SNMP Collector
ask_deploy_elastiflow_snmp() {
  if [ "$FULL_AUTO" -eq 1 ]; then
    echo "FULL_AUTO is set to 1. Skipping prompt and deploying Elastiflow SNMP Collector."
    deploy_elastiflow_snmp
    return 0
  fi
  
  while true; do
    read -p "Do you want to deploy ElastiFlow SNMP Collector? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        deploy_elastiflow_snmp
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying ElastiFlow SNMP Collector."
        return 0  # Exit the function but not the script
        ;;
      *)
        echo "Please answer y/yes or n/no."
        ;;
    esac
  done
}


ask_deploy_elastic_kibana() {
  if [ "$FULL_AUTO" -eq 1 ]; then
    echo "FULL_AUTO is set to 1. Skipping prompt and deploying Elastic and Kibana."
    deploy_elastic_kibana
    return 0
  fi

  while true; do
    read -p "Do you want to deploy Elastic and Kibana? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        deploy_elastic_kibana
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying Elastic and Kibana."
        return 0  # Exit the function but not the script
        ;;
      *)
        echo "Please answer y/yes or n/no."
        ;;
    esac
  done
}


print_message() {
  local message=$1
  local color=$2
  echo -e "${color}${message}${NC}"
}


install_prerequisites() {
  printf "\n\n\n*********Installing prerequisites...\n\n"

  echo "Updating package list..."
  apt-get -qq update > /dev/null 2>&1

  # List of packages to be installed
  packages=(jq net-tools git bc gpg curl wget unzip apt-transport-https openssl)

  # Loop through the list and install each package
  for package in "${packages[@]}"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
      echo "$package is already installed."
    else
      echo "Installing $package..."
      apt-get -qq install -y "$package" > /dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "$package installed successfully."
      else
        echo "Failed to install $package."
      fi
    fi
  done
}


load_env_vars(){
# Load the .env file from the current directory
if [ -f $INSTALL_DIR/.env ]; then
    source $INSTALL_DIR/.env
    printf "Environment variables loaded\n"
else
    echo "Error: .env file not found"
    exit 1
fi
}


install_dashboards() {
  local version=$1
  local filename=$2
  local schema=$3
  local directory=$4

  # Clone the repository
  git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/

  # Loop until Kibana is healthy or user chooses to abort
  while true; do
    check_kibana_status
    if [ $? -eq 0 ]; then
      break
    fi

    echo "⚠️ Kibana is not reachable or not healthy."
    read -p "Do you want to retry? (y/N): " retry_choice
    case "$retry_choice" in
      y|Y ) echo "Retrying..."; sleep 2 ;;
      * ) echo "Aborting installation."; rm -rf "/etc/elastiflow_for_elasticsearch/"; exit 1 ;;
    esac
  done

  # Path to the downloaded JSON file
  json_file="/etc/elastiflow_for_elasticsearch/kibana/$directory/kibana-$version-$filename-$schema.ndjson"
  if [ -e "$json_file" ]; then
    response=$(
      curl --insecure --silent --show-error --fail --connect-timeout 10 \
        -X POST \
        -u "elastic:$ELASTIC_PASSWORD" \
        "https://localhost:5601/api/saved_objects/_import?overwrite=true" \
        -H "kbn-xsrf: true" \
        --form file=@"$json_file"
    )

    dashboards_success=$(echo "$response" | jq -r '.success')

    if [ "$dashboards_success" == "true" ]; then
      print_message "$filename dashboards installed successfully." "$GREEN"
    else
      print_message "$filename dashboards not installed successfully." "$RED"
      echo "Debug: API response:"
      echo "$response"
    fi
  else
    echo "'$json_file' does not exist"
  fi

  # Clean up
  rm -rf "/etc/elastiflow_for_elasticsearch/"
}


# Function to download the required files (overwriting existing files)
download_files() {
  SCRIPT_DIR="$(dirname "$(realpath "$0")")"
  INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"
  
  # Create the directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"
  
  # Download files (force overwrite existing files)
  echo "Downloading setup files to $INSTALL_DIR..."
  curl -L -o "$INSTALL_DIR/.env" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env"
  curl -L -o "$INSTALL_DIR/elasticsearch_kibana_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_flow_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_flow_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_snmp_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_snmp_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_trap_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_trap_compose.yml"
  curl -L -o "$INSTALL_DIR/install_docker.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install_docker.sh"
}


# Function to check if Docker is installed and install if necessary
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. This is required."
    
  if [ "$FULL_AUTO" -eq 1 ]; then
    echo "FULL_AUTO is set to 1. Skipping prompt and deploying Docker."
      chmod +x "$INSTALL_DIR/install_docker.sh"
      bash "$INSTALL_DIR/install_docker.sh"
    return 0
  fi
    
    while true; do
      read -p "Do you want to install Docker? (y/n): " choice
      case "$choice" in
        [yY] | [yY][eE][sS] )
          echo "Installing Docker..."
          chmod +x "$INSTALL_DIR/install_docker.sh"
          bash "$INSTALL_DIR/install_docker.sh"

          # Verify if Docker is installed after running the install script
          if ! command -v docker &> /dev/null; then
            echo "Docker installation failed. Please check the installation process and try again."
            exit 1
          else
            echo "Docker installed successfully."
          fi
          break
          ;;
        [nN] | [nN][oO] )
          echo "Docker installation declined. Exiting..."
          exit 0
          ;;
        * )
          echo "Invalid input. Please enter 'y' for yes or 'n' for no."
          ;;
      esac
    done
  else
    echo "Docker is already installed."
  fi
}


tune_system() {
printf "\n\n\n*********System tuning starting...\n\n"
kernel_tuning=$(cat <<EOF
#####ElastiFlow flow tuning parameters######
#For light to moderate ingest rates (less than 75000 flows per second: https://docs.elastiflow.com/docs/flowcoll/requirements/
net.core.netdev_max_backlog=4096
net.core.rmem_default=262144
net.core.rmem_max=67108864
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_mem=2097152 4194304 8388608
vm.max_map_count=262144
#######################################
EOF
  )
  sed -i '/net.core.netdev_max_backlog=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_default=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_max=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_rmem_min=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_mem=/s/^/#/' /etc/sysctl.conf
  sed -i '/vm.max_map_count=/s/^/#/' /etc/sysctl.conf
  echo "$kernel_tuning" >> /etc/sysctl.conf
  sysctl -p
  echo "Kernel parameters updated in /etc/sysctl.conf with previous configurations commented out."

  echo '{"default-ulimits":{"memlock":{"name":"memlock","soft":-1,"hard":-1}},"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' | tee /etc/docker/daemon.json > /dev/null && systemctl restart docker

  printf "\n\n\n*********System tuning done...\n\n"
}


# Function to deploy Elastic and Kibana using Docker Compose
deploy_elastic_kibana() {
  echo "Deploying Elastic and Kibana..."
  tune_system
  cd "$INSTALL_DIR"
  docker compose -f elasticsearch_kibana_compose.yml up -d
  echo "Elastic and Kibana have been deployed successfully!"
}


# Function to deploy ElastiFlow Flow Collector using Docker Compose
deploy_elastiflow_flow() {
  if [ "$INSTALL_FLOWCOLL" != "1" ]; then
    echo "INSTALL_FLOWCOLL is not set to 1. Skipping deployment of ElastiFlow Flow Collector."
    return
  fi

  echo "Deploying ElastiFlow Flow Collector..."
  extract_elastiflow_flow
  cd "$INSTALL_DIR"

  # Set up directories
  mkdir -p /var/log/elastiflow
  chown -R 1000:1000 /var/log/elastiflow
  chmod -R 755 /var/log/elastiflow

  mkdir -p /var/lib/elastiflow/flowcoll
  chown -R 1000:1000 /var/lib/elastiflow/flowcoll
  chmod -R 755 /var/lib/elastiflow/flowcoll

  docker compose -f elastiflow_flow_compose.yml up -d

  # version, prod_filename, schema, prod_directory
  install_dashboards "$FLOW_DASHBOARDS_VERSION" "flow" "$FLOW_DASHBOARDS_SCHEMA" "flow" 

  echo "ElastiFlow Flow Collector has been deployed successfully!"
}


# Function to deploy ElastiFlow SNMP Collector using Docker Compose
deploy_elastiflow_snmp() {
  if [ "$INSTALL_SNMPCOLLTRAP" != "1" ]; then
    echo "INSTALL_SNMPCOLLTRAP is not set to 1. Skipping deployment of ElastiFlow SNMP Collector and Trap Collector."
    return
  fi

  echo "Deploying ElastiFlow SNMP Collector..."
  cd /etc/elastiflow
  git clone https://github.com/elastiflow/snmp.git
  cd "$INSTALL_DIR"

  docker compose -f elastiflow_snmp_compose.yml up -d

  mkdir -p /var/lib/elastiflow/trapcoll
  chown -R 1000:1000 /var/lib/elastiflow/trapcoll
  chmod -R 755 /var/lib/elastiflow/trapcoll

  docker compose -f elastiflow_trap_compose.yml up -d
  
  # version, prod_filename, schema, prod_directory
  install_dashboards "$SNMP_DASHBOARDS_VERSION" "snmp" "$SNMP_DASHBOARDS_SCHEMA" "snmp"  
  install_dashboards "$SNMP_TRAPS_DASHBOARDS_VERSION" "snmp-traps" "$SNMP_TRAPS_DASHBOARDS_SCHEMA" "snmp_traps" 
  
  echo "ElastiFlow SNMP Collector has been deployed successfully!"
}


# Function to download and extract ElastiFlow flow .deb
extract_elastiflow_flow() {
    # Set variables
    DEB_URL="https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_${ELASTIFLOW_FLOW_VERSION}_linux_amd64.deb"
    DEB_FILE="flow-collector_${ELASTIFLOW_FLOW_VERSION}_linux_amd64.deb"
    TEMP_DIR="/tmp/elastiflow_flow_deb"
    TARGET_DIR="/etc/elastiflow"

    # Download the .deb file
    echo "Downloading $DEB_URL..."
    wget -O "$DEB_FILE" "$DEB_URL"

    # Check if the temporary directory exists; if not, create it
    if [ ! -d "$TEMP_DIR" ]; then
        echo "Creating directory $TEMP_DIR..."
        mkdir -p "$TEMP_DIR"
    else
        echo "$TEMP_DIR already exists, skipping creation."
    fi

    # Extract the .deb file contents
    echo "Extracting $DEB_FILE..."
    dpkg-deb -x "$DEB_FILE" "$TEMP_DIR"

    # Copy /data/etc/elastiflow contents to /etc/elastiflow
    echo "Copying extracted files to $TARGET_DIR..."

    mkdir -p "$TARGET_DIR"
    chown -R 1000:1000 "$TARGET_DIR"
    chmod -R 755 "$TARGET_DIR"
    
    cp -r "$TEMP_DIR/etc/elastiflow/." "$TARGET_DIR/"

    # Cleanup
    echo "Cleaning up..."
    rm -rf "$TEMP_DIR" "$DEB_FILE"

    echo "ElastiFlow flow yml files have been extracted!"
}


get_physical_cores() {
  if command -v lscpu >/dev/null 2>&1; then
    # Use lscpu output to calculate: Sockets × Cores per Socket
    sockets=$(lscpu | awk -F: '/Socket\(s\)/ {gsub(/ /, "", $2); print $2}')
    cores_per_socket=$(lscpu | awk -F: '/Core\(s\) per socket/ {gsub(/ /, "", $2); print $2}')
    if [[ "$sockets" =~ ^[0-9]+$ && "$cores_per_socket" =~ ^[0-9]+$ ]]; then
      echo $((sockets * cores_per_socket))
      return 0
    fi
  fi

  # Fallback: Use /proc/cpuinfo to count unique physical ID + core ID pairs
  if [ -f /proc/cpuinfo ]; then
    awk '
      /^physical id/ {pid=$4}
      /^core id/ {cid=$4; cores[pid ":" cid]=1}
      END {print length(cores)}
    ' /proc/cpuinfo
    return 0
  fi

  echo "Unable to determine physical CPU core count" >&2
  return 1
}


get_total_ram() {
  if [ -f /proc/meminfo ]; then
    awk '/^MemTotal:/ {printf "%.2f\n", $2 / 1024 / 1024}' /proc/meminfo
  else
    echo "Unable to determine total RAM" >&2
    return 1
  fi
}

get_free_disk_space() {
  df -h --output=avail / | tail -n 1
}

check_hardware()
{
  cores=$(get_physical_cores)
  total_ram=$(get_total_ram)          # Expected in GB (float)
  free_space=$(get_free_disk_space)   # Expected in GB (float)

  warn=false
  problems=""

  # Use bc for floating-point comparison
  if (( $(echo "$total_ram < 16" | bc -l) )); then
    problems+="  - Installed RAM is less than 16 GB (detected: ${total_ram} GB)\n"
    warn=true
  fi

  if (( $(echo "$free_space < 400" | bc -l) )); then
    problems+="  - Free disk space is less than 400 GB (detected: ${free_space} GB)\n"
    warn=true
  fi

  # Cores are integer — safe with [ ]
  if [ "$cores" -lt 8 ]; then
    problems+="  - Physical CPU cores are less than 8 (detected: ${cores})\n"
    warn=true
  fi

  if [ "$warn" = true ]; then
    echo -e "⚠️ Hardware requirements check failed:\n$problems"
    read -p "Do you want to continue anyway? (y/N): " choice
    case "$choice" in
      y|Y ) echo "Continuing...";;
      * ) echo "Aborting."; exit 1;;
    esac
  fi
}



check_kibana_status() {
    url="https://localhost:5601/api/status"
    timeout=120  # 2 minutes
    interval=1  # Check every 1 second
    elapsed_time=0

    while [ $elapsed_time -lt $timeout ]; do
        # Fetch the status and check if it's 'available'
        status=$(curl -k -s "$url" | jq -r '.status.overall.level')
        
        if [ "$status" == "available" ]; then
            echo "[$(date)] Kibana is ready to be logged in. Status: $status"
            return 0  # Exit with success
        else
            echo "[$(date)] Kibana is not ready yet. Status: $status"
        fi
        
        # Wait for 1 second before checking again
        sleep $interval
        
        # Increment elapsed time by interval
        elapsed_time=$((elapsed_time + interval))
    done

    echo "[$(date)] Kibana not ready within the timeout period"
    return 1  # Exit with failure
}


# Main script execution
check_for_ubuntu
check_root
install_prerequisites #before check_hardware since it requires bc
check_hardware
check_rw
download_files
edit_env_file
load_env_vars
remove_docker_snap
check_docker
ask_deploy_elastic_kibana
ask_deploy_elastiflow_flow
ask_deploy_elastiflow_snmp
install_flow_blocker
if check_system_health; then
  echo "System is healthy."
else
  echo "System is NOT healthy."
fi

