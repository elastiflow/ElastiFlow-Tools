#!/bin/bash

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ----- Only allow Rocky Linux 7 or 8 -----
if [ ! -f /etc/os-release ]; then
  echo "Unable to detect OS. This script only works on Rocky Linux 7 or 8."
  exit 1
fi

. /etc/os-release

# Check that it's actually Rocky and that VERSION_ID is 7 or 8
if [ "$ID" != "rocky" ] || { [[ ! "$VERSION_ID" =~ ^7\. ]] && [[ ! "$VERSION_ID" =~ ^8\. ]]; }; then
  echo "Unsupported OS. This script only works on Rocky Linux 7 or 8."
  exit 1
fi
# -----------------------------------------

# Define Global Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"

# Function to check if the user is root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

check_all_containers_up_for_10_seconds() {
  local check_interval=1  # Check every 1 second
  local required_time=10  # Total check time of 10 seconds
  local elapsed_time=0
  declare -A container_status_summary  # Associative array to store status of each container

  # Define color codes
  local GREEN='\033[0;32m'
  local RED='\033[0;31m'
  local NC='\033[0m' # No Color

  # Get a list of all running Docker containers' IDs and Names
  local containers=($(docker ps --format "{{.ID}}:{{.Names}}"))

  if [ ${#containers[@]} -eq 0 ]; then
    echo "No running containers found."
    return 1
  fi

  echo "Checking if all Docker containers remain 'Up' for at least 10 seconds..."

  # Initialize the summary array with "stable" for each container
  for container in "${containers[@]}"; do
    container_id=$(echo "$container" | cut -d':' -f1)
    container_name=$(echo "$container" | cut -d':' -f2)
    container_status_summary["$container_name"]="stable"
  done

  # Check each container every second
  while [ $elapsed_time -lt $required_time ]; do
    for container in "${containers[@]}"; do
      container_id=$(echo "$container" | cut -d':' -f1)
      container_name=$(echo "$container" | cut -d':' -f2)

      # Check the status of the container using docker ps
      status=$(docker ps --filter "id=$container_id" --format "{{.Status}}")

      # If the container is not "Up", mark it as "not stable"
      if [[ "$status" != Up* ]]; then
        container_status_summary["$container_name"]="not stable"
      fi
    done

    sleep $check_interval
    elapsed_time=$((elapsed_time + check_interval))
  done

  # Output the summary of all containers (without duplicates)
  echo -e "\nSummary of Docker container statuses after $required_time seconds:"
  for container_name in "${!container_status_summary[@]}"; do
    if [ "${container_status_summary[$container_name]}" == "stable" ]; then
      print_message "Container '$container_name' is stable." "$GREEN"
    else
      print_message "Container '$container_name' is not stable." "$RED"
    fi
  done
}

edit_env_file() {
  local env_file="$INSTALL_DIR/.env"  # Change this path to your actual .env file location
  local answer

  while true; do
    echo "Would you like to edit the .env file before proceeding? (y/n) [Default: no in 20 seconds]"
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

check_system_health(){
  printf "\n\n*********************************"
  printf "*********************************\n"
  check_all_containers_up_for_10_seconds
  check_elastic_ready
  check_kibana_ready
  check_elastiflow_flow_open_ports
  # check_elastiflow_readyz
  check_elastiflow_livez
  get_dashboard_status "ElastiFlow (flow): Overview"
  #get_dashboard_status "ElastiFlow (telemetry): Overview"
}

get_dashboard_status(){
  get_dashboard_url "$1"
  if [ "$dashboard_url" == "Dashboard not found" ]; then
    print_message "Dashboard $1: URL: $dashboard_url" "$RED"
  else
    print_message "Dashboard $1: URL: $dashboard_url" "$GREEN"
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
  local kibana_url="http://$ip_address:5601"
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  local response=$(curl -s -u "elastic:$ELASTIC_PASSWORD" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
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

check_elastiflow_livez(){
  response=$(curl -s http://localhost:8080/livez)
  if echo "$response" | grep -q "200"; then
    print_message "ElastiFlow Flow Collector is $response" "$GREEN"
  else
    print_message "ElastiFlow Flow Collector Livez: $response" "$RED"
  fi
}

check_elastiflow_flow_open_ports() {
  # Path to the .env file (you can adjust the path if necessary)
  local env_file="$INSTALL_DIR/elastiflow_flow_compose.yml"

  # Extract the EF_FLOW_SERVER_UDP_PORT variable from the .env file (ignoring commented lines)
  local port_list=$(grep -v '^#' "$env_file" | grep 'EF_FLOW_SERVER_UDP_PORT' | cut -d ':' -f2 | tr -d ' ')

  # Check if the variable is empty
  if [ -z "$port_list" ]; then
    echo "No ports found in the EF_FLOW_SERVER_UDP_PORT variable."
    return
  fi

  # Split the port list by commas and check each port
  IFS=',' read -ra ports <<< "$port_list"
  for port in "${ports[@]}"; do
    if netstat -tuln | grep -q ":$port"; then
      print_message "ElastiFlow Flow Collector port $port is open." "$GREEN"
    else
      print_message "ElastiFlow Flow Collector is not ready for flow on $port." "$RED"
    fi
  done
}

check_elastic_ready(){
  curl_result=$(curl -s -k -u "elastic:$ELASTIC_PASSWORD" https://localhost:9200)
  search_text='"tagline" : "You Know, for Search"'
  if echo "$curl_result" | grep -q "$search_text"; then
    print_message "Elastic is ready. Used authenticated curl." "$GREEN"
  else
    print_message "Elastic is not ready." "$RED"
    echo "$curl_result"
  fi
}

check_kibana_ready(){
  response=$(curl -s -X GET "http://localhost:5601/api/status")
  if [[ $response == *'"status":{"overall":{"level":"available"}}'* ]]; then
    print_message "Kibana is ready. Used curl." "$GREEN"
  else
    print_message "Kibana is not ready" "$RED"
    echo "$response"
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
  printf "\n\n\n*********Installing prerequisites on Rocky Linux...\n\n"
  echo "Updating package list with dnf..."
  dnf -y makecache > /dev/null 2>&1

  # List of packages to be installed on Rocky
  packages=(jq net-tools git bc gnupg2 curl wget unzip openssl epel-release dpkg)


  # Loop through the list and install each package
  for package in "${packages[@]}"; do
    if rpm -q "$package" &>/dev/null; then
      echo "$package is already installed."
    else
      echo "Installing $package..."
      dnf -y install "$package" > /dev/null 2>&1
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

  check_kibana_status

  # Path to the downloaded JSON file
  json_file="/etc/elastiflow_for_elasticsearch/kibana/$directory/kibana-$version-$filename-$schema.ndjson"
  if [ -e "$json_file" ]; then
    response=$(curl --silent --show-error --fail --connect-timeout 10 -X POST -u "elastic:$ELASTIC_PASSWORD" \
      "localhost:5601/api/saved_objects/_import?overwrite=true" \
      -H "kbn-xsrf: true" \
      --form file=@"$json_file" \
      -H 'kbn-xsrf: true')

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
  curl -L -o "$INSTALL_DIR/install_docker_rocky.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/rocky_7-8/install_docker_rocky.sh"
}

# Function to check if Docker is installed and install if necessary
check_docker() {
  # If Docker is already installed, do nothing.
  if command -v docker &> /dev/null; then
    echo "Docker is already installed."
    return 0
  fi

  # Docker not found, attempt installation
  echo "Docker is not installed. Installing..."
  chmod +x "$INSTALL_DIR/install_docker_rocky.sh" || {
    echo "Failed to set execute permission on install_docker_rocky.sh."
    exit 1
  }

  bash "$INSTALL_DIR/install_docker_rocky.sh" || {
    echo "Docker install script encountered an error."
    exit 1
  }

  # Verify installation
  if ! command -v docker &> /dev/null; then
    echo "Docker installation failed. Please check the installation process."
    exit 1
  fi

  echo "Docker installed successfully."
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

  echo '{"default-ulimits": {"memlock": {"name": "memlock", "soft": -1, "hard": -1}}}' | tee /etc/docker/daemon.json > /dev/null && systemctl restart docker

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
  echo "Deploying ElastiFlow Flow Collector..."
  extract_elastiflow_flow
  cd "$INSTALL_DIR"
  #set up directories
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

check_kibana_status() {
  url="http://localhost:5601/api/status"
  timeout=120  # 2 minutes
  interval=1   # Check every 1 second
  elapsed_time=0

  while [ $elapsed_time -lt $timeout ]; do
    # Fetch the status and check if it's 'available'
    status=$(curl -s "$url" | jq -r '.status.overall.level')
    if [ "$status" = "available" ]; then
      echo "[ $(date) ] Kibana is ready to be logged in. Status: $status"
      return 0  # Exit with success
    else
      echo "[ $(date) ] Kibana is not ready yet. Status: $status"
    fi

    sleep $interval
    elapsed_time=$((elapsed_time + interval))
  done

  echo "[ $(date) ] Kibana not ready within the timeout period"
  return 1  # Exit with failure
}

# Main script execution
check_root
install_prerequisites
download_files
edit_env_file
load_env_vars
check_docker
ask_deploy_elastic_kibana
ask_deploy_elastiflow_flow
#ask_deploy_elastiflow_snmp
check_system_health
