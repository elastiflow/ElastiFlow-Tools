#!/bin/bash
# Install docker with ElastiFlow and Elastisearch contaiiners
#


# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No


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
        sudo nano "$env_file"  # Open the .env file with sudo nano
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

check_opensearch_ready(){
  curl_result=$(curl -s -k -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" https://localhost:9200 | jq -r '.name')
  
    #  search_text='"tagline" : "You Know, for Search"'
     if [ "$curl_result" == "opensearch" ]; then
       print_message "Opensearch is ready. Used authenticated curl." "$GREEN"
     else
       print_message "Opensearch is not ready." "$RED"
       echo "$curl_result"
     fi
}

check_system_health(){
  printf "\n\n*********************************"
  printf "*********************************\n"
  check_all_containers_up_for_10_seconds
  check_opensearch_ready
  check_kibana_ready
  check_elastiflow_flow_open_ports
  check_elastiflow_readyz
  get_dashboard_status "ElastiFlow (flow): Overview"
#   get_dashboard_status "ElastiFlow (telemetry): Overview"
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
  local response=$(curl -s -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'osd-xsrf: true')
  local dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  if [ -z "$dashboard_id" ]; then
    dashboard_url="Dashboard not found"
  else
    dashboard_url="$kibana_url/app/kibana#/dashboard/$dashboard_id"
  fi
}


 check_elastiflow_readyz(){
   response=$(curl -s http://localhost:8080/metrics | grep ^app_info | awk -F'env="' '{print $2}' | awk -F'"' '{print $1}')
      if [ "$response" == "docker" ]; then
        print_message "ElastiFlow Flow Collector is running" "$GREEN"
      else
        print_message "ElastiFlow Flow Collector not running properly: $response" "$RED"
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

check_kibana_ready(){
  response=$(curl -s -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -X GET "http://localhost:5601/api/status" | jq -r '.status.overall.state')
    
    if [ "$response" == "green" ]; then
        print_message "Opensearch dashboard is ready. Used curl." "$GREEN"
    else
        print_message "Opensearch dashboard is not ready" "$RED"
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

# Function to deploy Opensearch using Docker Compose
deploy_opensearch() {
  echo "Deploying Opensearch..."
  disable_swap_if_swapfile_in_use
  tune_system
  generate_saved_objects_enc_key
  cd "$INSTALL_DIR"
  docker compose -f opensearch_compose.yml up -d
  echo "Opensearch has been deployed successfully!"
}

ask_deploy_opensearch() {
  if [ "$FULL_AUTO" -eq 1 ]; then
    echo "FULL_AUTO is set to 1. Skipping prompt and deploying Opensearch."
    deploy_opensearch
    return 0
  fi

  while true; do
    read -p "Do you want to deploy Opensearch? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        deploy_opensearch
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying Opensearch."
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
#    source /home/user/elastiflow_install/.env
    source $INSTALL_DIR/.env
    printf "Environment variables loaded\n"
else
    echo "Error: .env file not found"
    exit 1
fi
}



install_dashboards() {
  local elastiflow_product=$1

  # Clone the repository
  git clone https://github.com/elastiflow/elastiflow_for_opensearch.git /etc/elastiflow_for_opensearch/
  
  check_kibana_status

  # Path to the downloaded JSON fil
  json_file="/etc/elastiflow_for_opensearch/dashboards/$elastiflow_product/dashboards-$SNMP_DASHBOARDS_VERSION-$elastiflow_product-$DASHBOARDS_CODEX_ECS.ndjson"

  response=$(curl --silent --show-error --fail --connect-timeout 10 -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -X POST  \
    "localhost:5601/api/saved_objects/_import?overwrite=true" \
    -H "osd-xsrf: true" \
    --form file=@"$json_file" )

  dashboards_success=$(echo "$response" | jq -r '.success')

  if [ "$dashboards_success" == "true" ]; then
    print_message "$elastiflow_product dashboards installed successfully." "$GREEN"
  else
    print_message "$elastiflow_product dashboards not installed successfully." "$RED"
    echo "Debug: API response:"
    echo "$response"
  fi

  rm -rf "/etc/elastiflow_for_opensearch/"
}



# Function to download the required files (overwriting existing files)
download_files() {
  SCRIPT_DIR="$(dirname "$(realpath "$0")")"
  INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"
  
  # Create the directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"
  
  # Download files (force overwrite existing files)
  echo "Downloading setup files to $INSTALL_DIR..."
  curl -L -o "$INSTALL_DIR/.env" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/opensearch/.env"
  curl -L -o "$INSTALL_DIR/opensearch_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/opensearch/opensearch_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_flow_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/opensearch/elastiflow_flow_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_snmp_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/opensearch/elastiflow_snmp_compose.yml"
  curl -L -o "$INSTALL_DIR/install_docker.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/redhat_elasticsearch/install_docker.sh"
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
  printf "\n\n\n*********System tuning done...\n\n"
}


# Function to deploy Elastic and Kibana using Docker Compose
deploy_elastic_kibana() {
  echo "Deploying Elastic and Kibana..."
  disable_swap_if_swapfile_in_use
  tune_system
  generate_saved_objects_enc_key
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
  install_dashboards "flow"
  echo "ElastiFlow Flow Collector has been deployed successfully!"
}


# Function to deploy ElastiFlow SNMP Collector using Docker Compose
deploy_elastiflow_snmp() {
  echo "Deploying ElastiFlow SNMP Collector..."
  cd /etc/elastiflow
  git clone https://github.com/elastiflow/snmp.git
  cd "$INSTALL_DIR"
  docker compose -f elastiflow_snmp_compose.yml up -d
  install_dashboards "snmp"
  echo "ElastiFlow SNMP Collector has been deployed successfully!"
}


# Function to check and disable swap if any swap file is in use
disable_swap_if_swapfile_in_use() {
  
printf "\n\n\n*********Disabling swap file if present...\n\n"

    # Check if swap is on
    swap_status=$(swapon --show)

    if [ -n "$swap_status" ]; then
        echo "Swap is currently on."

        # Get the swap file name if it's in use (filtering for file type swaps)
        swapfile=$(swapon --show | awk '$2 == "file" {print $1}')

        if [ -n "$swapfile" ]; then
            echo "$swapfile is in use."

            # Turn off swap
            echo "Turning off swap..."
            swapoff -a

            # Check if swapoff was successful
            if [ $? -eq 0 ]; then
                echo "Swap has been turned off."

                # Delete the detected swap file
                echo "Deleting $swapfile..."
                rm -f "$swapfile"

                if [ $? -eq 0 ]; then
                    echo "$swapfile has been deleted."
                else
                    echo "Failed to delete $swapfile."
                fi
            else
                echo "Failed to turn off swap."
            fi
        else
            echo "No swap file found in use."
        fi
    else
        echo "Swap is currently off."
    fi
}


# Function to download and extract ElastiFlow flow 
extract_elastiflow_flow() {
    # Set variables
    RPM_URL="https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector-${ELASTIFLOW_FLOW_VERSION}-1.x86_64.rpm"
    RPM_FILE="flow-collector_${ELASTIFLOW_FLOW_VERSION}-1.x86_64.rpm"
    TEMP_DIR="/tmp/elastiflow_flow_rpm"
    TARGET_DIR="/etc/elastiflow"

    # Download the .deb file
    echo "Downloading $RPM_URL..."
    wget -O "$RPM_FILE" "$RPM_URL"

    # Check if the temporary directory exists; if not, create it
    if [ ! -d "$TEMP_DIR" ]; then
        echo "Creating directory $TEMP_DIR..."
        mkdir -p "$TEMP_DIR"
    else
        echo "$TEMP_DIR already exists, skipping creation."
    fi

    # Extract the .deb file contents
    echo "Extracting $RPM_FILE..."
    rpm2cpio "$RPM_FILE" | cpio -idmv -D "$TEMP_DIR"

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


# create xpack.encryptedSavedObjects.encryptionKey and append to .env
generate_saved_objects_enc_key() {
  XPACK_SAVED_OBJECTS_KEY=$(openssl rand -base64 32)
  echo "XPACK_SAVED_OBJECTS_KEY=${XPACK_SAVED_OBJECTS_KEY}" | tee -a $INSTALL_DIR/.env > /dev/null
}

check_kibana_status() {
    url="http://localhost:5601/api/status"
    timeout=120  # 2 minutes
    interval=2  # Check every 1 second
    elapsed_time=0

    while [ $elapsed_time -lt $timeout ]; do
        # Fetch the status and check if it's 'available'
        status=$(curl -uadmin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -s "$url" | jq -r '.status.overall.state')
        
        if [ "$status" == "green" ]; then
            echo "[$(date)] Opensearch Dashboards is ready to be logged in. Status: $status"
            return 0  # Exit with success
        else
            echo "[$(date)] Opensearch Dashboards is not ready yet. Status: $status"
        fi
        
        # Wait for 1 second before checking again
        sleep $interval
        
        # Increment elapsed time by interval
        elapsed_time=$((elapsed_time + interval))
    done

    echo "[$(date)] Opensearch Dashboards not ready within the timeout period"
    return 1  # Exit with failure
}

# Main script execution
check_root
install_prerequisites
download_files
edit_env_file
load_env_vars
check_docker
ask_deploy_opensearch
ask_deploy_elastiflow_flow
# ask_deploy_elastiflow_snmp
check_system_health