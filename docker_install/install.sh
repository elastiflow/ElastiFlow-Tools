#!/bin/bash

# Function to check if the user is root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

# Function to ask the user if they want to deploy ElastiFlow Flow Collector
ask_deploy_elastiflow_flow() {
  while true; do
    read -p "Do you want to deploy ElastiFlow Flow Collector? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying ElastiFlow Flow Collector."
        exit 0
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
    echo "Installing $package..."
    apt-get -qq install -y "$package" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "$package installed successfully."
    else
      echo "Failed to install $package."
    fi
  done
}

load_env(){
# Load the .env file from the current directory
if [ -f $INSTALL_DIR/.env ]; then
    source /home/user/elastiflow_install/.env
    printf "Environment variables loaded\n"
else
    echo "Error: .env file not found"
    exit 1
fi
}


install_dashboards() {
  local elastiflow_product=$1

  # Clone the repository
  git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/
  
  check_kibana_status

  # Path to the downloaded JSON file
  json_file="/etc/elastiflow_for_elasticsearch/kibana/$elastiflow_product/kibana-$DASHBOARDS_VERSION-$elastiflow_product-$DASHBOARDS_CODEX_ECS.ndjson"

  response=$(curl --silent --show-error --fail --connect-timeout 10 -X POST -u "elastic:${ELASTIC_PASSWORD}" \
    "localhost:5601/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" \
    --form file=@"$json_file" \
    -H 'kbn-xsrf: true')

  dashboards_success=$(echo "$response" | jq -r '.success')

  if [ "$dashboards_success" == "true" ]; then
    print_message "$elastiflow_product dashboards installed successfully." "$GREEN"
  else
    print_message "$elastiflow_product dashboards not installed successfully." "$RED"
    echo "Debug: API response:"
    echo "$response"
  fi

  rm -rf "/etc/elastiflow_for_elasticsearch/"
}


# Function to ask the user if they want to deploy ElastiFlow SNMP Collector
ask_deploy_elastiflow_snmp() {
  while true; do
    read -p "Do you want to deploy ElastiFlow SNMP Collector? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying ElastiFlow SNMP Collector."
        exit 0
        ;;
      *)
        echo "Please answer y/yes or n/no."
        ;;
    esac
  done
}

# Function to download the required files (overwriting existing files)
download_files() {
  SCRIPT_DIR="$(dirname "$(realpath "$0")")"
  INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"
  
  # Create the directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"
  
  # Download files (force overwrite existing files)
  echo "Downloading files to $INSTALL_DIR..."
  curl -L -o "$INSTALL_DIR/.env" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env"
  curl -L -o "$INSTALL_DIR/elasticsearch_kibana_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_flow_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_flow_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_snmp_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_snmp_compose.yml"
  curl -L -o "$INSTALL_DIR/install_docker.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install_docker.sh"
}

# Function to check if Docker is installed and install if necessary
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. This is required."
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


# Function to deploy ElastiFlow Flow Collector using Docker Compose
deploy_elastic_elastiflow_flow() {
  echo "Deploying ElastiFlow Flow..."
  cd "$INSTALL_DIR"
  docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_flow_compose.yml up -d
  install_dashboards "flow"
  echo "ElastiFlow Flow Collector has been deployed successfully!"

}

# Function to deploy ElastiFlow SNMP Collector using Docker Compose
deploy_elastic_elastiflow_snmp() {
  echo "Deploying ElastiFlow SNMP..."
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


# Function to download and extract ElastiFlow flow .deb
extract_elastiflow_flow() {
    # Set variables
    DEB_URL="https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb"
    DEB_FILE="flow-collector_7.2.2_linux_amd64.deb"
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
    interval=1  # Check every 1 second
    elapsed_time=0

    while [ $elapsed_time -lt $timeout ]; do
        # Fetch the status and check if it's 'available'
        status=$(curl -s "$url" | jq -r '.status.overall.level')
        
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
check_root
ask_deploy_elastiflow_flow
disable_swap_if_swapfile_in_use
tune_system
download_files
load_env
generate_saved_objects_enc_key
check_docker
extract_elastiflow_flow
deploy_elastic_elastiflow_flow
ask_deploy_elastiflow_snmp
deploy_elastic_elastiflow_snmp
