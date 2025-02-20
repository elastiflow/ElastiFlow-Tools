#!/bin/bash

# Version: 3.0.4.6

########################################################
# ELASTIFLOW_CONFIGURATION
########################################################
flowcoll_version="7.7.2"
# If you do not have an ElastiFlow Account ID and License Key, please go here: https://elastiflow.com/get-started
ef_license_key=""
ef_account_id=""
frps=0

########################################################
# DATA PLATFORM CONFIGURATION
########################################################
#note: Elastic 8.16.4 is the last version to have free TSDS
elastic_tsds="true"
elasticsearch_version="8.16.4"
kibana_version="8.16.4"
flow_dashboards_version="8.14.x"
#If you are using codex schema, this should be set to "codex". Otherwise set to "ecs"
flow_dashboards_codex_ecs="codex"
#If you are using codex schema, this should be set to "false". Otherwise, set to "true", for ecs.
ecs_enable="false"
elastic_username="elastic"
elastic_password="elastic"
opensearch_version=2.18.0
opensearch_username="admin"
opensearch_password="yourStrongPassword123!"
osd_flow_dashboards_version="2.14.x"
########################################################

# Create a timestamped log file in the current directory
LOG_FILE="$PWD/elastiflow_install_$(date +'%Y%m%d_%H%M%S').log"

# Redirect all output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

# run script in non-interactive mode by default
export DEBIAN_FRONTEND=noninteractive

flowcoll_config_path="/etc/elastiflow/flowcoll.yml"
DATA_PLATFORM=''
# vm specs 64 gigs ram, 16 vcpus, 2 TB disk, license for up to 64k FPS, 1 week retention at 16K FPS


#leave blank
osversion=""

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check for and install updates
install_os_updates() {
  print_message "Checking for and installing OS updates..." "$GREEN"

  # Update package list
  apt-get -qq update

  # Upgrade packages without prompting
  apt-get -qq -y upgrade

  # Perform a distribution upgrade without prompting
  apt-get -qq -y dist-upgrade

  # Clean up
  apt-get -qq -y autoremove
  apt-get -qq -y autoclean

  print_message "Updates installed successfully." "$GREEN"
}

select_search_engine(){
  #!/bin/bash
  # Define the options
  options=(
      "Elasticsearch"
      "Opensearch"
      "Exit install script"
  )
  # Function to display options
  display_options() {
      echo "Select the search engine for ElastiFlow to use:"
      for i in "${!options[@]}"; do
          echo "$((i + 1)). ${options[i]}"
      done
  }
  # Prompt the user for input
  while true; do
      display_options
      read -rp "Enter the number corresponding to your choice: " choice
      # Validate the input
      if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
          echo "You selected: ${options[choice - 1]}"
          break
      else
          echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
      fi
  done
  # Perform actions based on the user's choice
  case "$choice" in
      1)
          DATA_PLATFORM='Elastic'
          ;;
      2)
          DATA_PLATFORM='Opensearch'
          ;;
      3)
          echo "Exiting..."
          exit 0
          ;;
  esac
}


sanitize_system() {

print_message "Finding and cleaning previous / competing installations..." "$GREEN"

  # Define services, directories, and keywords
  SERVICES=("flowcoll" "elasticsearch" "kibana" "opensearch" "opensearch-dashboards" "snmpcoll")
  KEYWORDS=("kibana" "elasticsearch" "flowcoll" "elastiflow" "opensearch" "opensearch-dashboards" "snmpcoll" "elastic.co" "elastic")
  PORTS=(8080 5601 9200 2055 4739 6343 9995)

  # Stop services
  for SERVICE in "${SERVICES[@]}"; do
    if systemctl list-units --type=service --all | grep -q "$SERVICE.service"; then
      echo "Stopping service: $SERVICE"
      systemctl stop "$SERVICE"
      systemctl disable "$SERVICE"
      echo "Service $SERVICE stopped and disabled."
    else
      echo "Service $SERVICE not found. Skipping..."
    fi
  done

  # Kill processes using specific ports and disable offending services
  for PORT in "${PORTS[@]}"; do
    echo "Stopping processes using port: $PORT"
    PROCESSES=$(lsof -i :$PORT | awk 'NR>1 {print $2}')
    if [ -n "$PROCESSES" ]; then
      echo "$PROCESSES" | xargs -r kill -9
      echo "Processes using port $PORT stopped."
      for PID in $PROCESSES; do
        SERVICE_NAME=$(ps -p $PID -o comm=)
        if systemctl list-units --type=service --all | grep -q "$SERVICE_NAME.service"; then
          echo "Disabling service: $SERVICE_NAME"
          systemctl disable "$SERVICE_NAME"
          echo "Service $SERVICE_NAME disabled."
        fi
      done
    else
      echo "No processes found on port $PORT."
    fi
  done

  # Purge packages
  for SERVICE in "${SERVICES[@]}"; do
    if dpkg -l | grep -q "$SERVICE"; then
      echo "Purging package: $SERVICE"
      apt purge --yes "$SERVICE"
      echo "Package $SERVICE purged."
    else
      echo "Package $SERVICE not found. Skipping..."
    fi
  done

  # Purge JRE
  if dpkg -l | grep -q "openjdk"; then
    echo "Purging JRE packages"
    apt purge --yes "openjdk*"
    echo "JRE packages purged."
  else
    echo "JRE packages not found. Skipping..."
  fi

  # Delete directories and files matching keywords
  for KEYWORD in "${KEYWORDS[@]}"; do
    echo "Deleting directories containing: $KEYWORD"
    find / -type d -name "*${KEYWORD}*" -exec rm -rf {} \; 2>/dev/null
    echo "Directories containing $KEYWORD deleted."

    echo "Deleting files containing: $KEYWORD"
    find / -type f -name "*${KEYWORD}*" -exec rm -f {} \; 2>/dev/null
    echo "Files containing $KEYWORD deleted."
  done

  # Clean up unused dependencies
  echo "Cleaning up unused dependencies..."
  apt autoremove --yes

  # Summary
  for SERVICE in "${SERVICES[@]}"; do
    echo "Checked service: $SERVICE - stopped, disabled, and purged if present."
  done

  for KEYWORD in "${KEYWORDS[@]}"; do
    echo "Checked for directories and files containing: $KEYWORD - deleted if present."
  done

  for PORT in "${PORTS[@]}"; do
    echo "Checked and stopped processes using port: $PORT"
  done

  echo "Unused dependencies removed. Cleanup complete."
}



create_banner() {
  # Backup the existing /etc/issue file
  cp /etc/issue /etc/issue.bak

  # Create the new banner content
  banner_content=$(cat << EOF

@@@@@@@@@@@@@@ @@@@@                                @@@@     @@@@  @@@@@@@@@@@@@@@ @@@@
@@@@@@@@@@@@@  @@@@@                               @@@@@     @@@@  @@@@@@@@@@@@@@  @@@@
@@@@           @@@@@     @@@@@@        @@@@@@    @@@@@@@@@@  @@@@  @@@@@           @@@@     @@@@@@@@   @@@@     @@@@     @@@@
@@@@           @@@@@  @@@@@@@@@@@@  @@@@@@@@@@@@ @@@@@@@@@@        @@@@@           @@@@   @@@@@@@@@@@  @@@@@    @@@@@    @@@@
@@@@@@@@@@     @@@@@ @@@@@@  @@@@@  @@@@@  @@@@@@@@@@@@@@@   @@@@  @@@@@@@@@@@     @@@@  @@@@@@@@@@@@@@ @@@@   @@@@@@   @@@@@
@@@@@@@@@      @@@@@          @@@@@ @@@@@@@@       @@@@@     @@@@  @@@@@@@@@@      @@@@ @@@@@     @@@@@ @@@@   @@@@@@@  @@@@
@@@@@@@@       @@@@@  @@@@@@@@@@@@@ @@@@@@@@@@@@   @@@@@     @@@@  @@@@@@@@@       @@@@ @@@@@      @@@@  @@@@ @@@@ @@@ @@@@@
@@@@           @@@@@ @@@@@@@@@@@@@@    @@@@@@@@@@  @@@@@     @@@@  @@@@@           @@@@ @@@@@     @@@@@  @@@@ @@@  @@@@@@@@
@@@@@@@@@@@@@@ @@@@@ @@@@    @@@@@@@@@@@    @@@@@  @@@@@@    @@@@  @@@@@           @@@@ @@@@@@   @@@@@@   @@@@@@@   @@@@@@@
@@@@@@@@@@@@@@ @@@@@ @@@@@@@@@@@@@@ @@@@@@@@@@@@    @@@@@@@  @@@@  @@@@@           @@@@  @@@@@@@@@@@@@    @@@@@@    @@@@@@
@@@@@@@@@@@@@  @@@@@  @@@@@@@ @@@@@  @@@@@@@@@@      @@@@@@  @@@@  @@@@@           @@@@    @@@@@@@@@       @@@@@     @@@@@

=======================================

Welcome to ElastiFlow Virtual Appliance

=======================================

Log in and type sudo ./configure.sh to get started.

Setup Instructions:  https://sites.google.com/elastiflow.com/elastiflow
Documentation:       https://docs.elastiflow.com
Community:           https://forum.elastiflow.com
Slack:               https://elastiflowcommunity.slack.com

EOF
  )

  # Write the new content to /etc/issue
  echo "$banner_content" > /etc/issue

  # Write the SSH banner content to /etc/ssh/ssh_banner
  echo "$banner_content" > /etc/ssh/ssh_banner

  # Update the SSH configuration to use the banner
  if ! grep -q "^Banner /etc/ssh/ssh_banner" /etc/ssh/sshd_config; then
    echo "Banner /etc/ssh/ssh_banner" >> /etc/ssh/sshd_config
  fi

  # Restart the SSH service to apply the changes
  systemctl restart ssh.service
}


disable_predictable_network_names() {
    # Check if /etc/network/interfaces exists and replace interface names with eth0
    if [ -e /etc/network/interfaces ]; then
        sed -i 's/en[[:alnum:]]*/eth0/g' /etc/network/interfaces
    fi

    # Modify GRUB configuration to disable predictable network interface names
    sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1"/g' /etc/default/grub

    # Update GRUB to apply changes
    update-grub
}


print_message() {
  local message=$1
  local color=$2
  echo -e "${color}${message}${NC}"
}


# Function to clean the apt cache
clean_apt_cache() {
    apt-get clean
}

# Function to clean old kernels
clean_old_kernels() {
    apt-get autoremove --purge -y
}

# Function to clean orphaned packages
clean_orphaned_packages() {
    apt-get autoremove -y
}

# Function to clean thumbnail cache
clean_thumbnail_cache() {
    rm -rf ~/.cache/thumbnails/*
}

# Function to clean log files
clean_log_files() {
    find /var/log -type f -name "*.log" -delete
}

# Function to clean temporary files
clean_temp_files() {
    rm -rf /tmp/*
    rm -rf /var/tmp/*
}

# Function to remove unnecessary files
clean_unnecessary_files() {
    apt-get autoclean
    rm -rf /etc/elastiflow_for_elasticsearch
}

# Function to clean system junk files
clean_system_junk() {
    echo "Cleaning up..."
    clean_apt_cache
    clean_old_kernels
    clean_orphaned_packages
    clean_thumbnail_cache
    clean_log_files
    clean_temp_files
    clean_unnecessary_files
    echo "Cleaned up."
}


# Function to check and disable swap if any swap file is in use
disable_swap_if_swapfile_in_use() {

print_message "Disabling swap file if present..." "$GREEN"

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

configure_snapshot_repo() {
  # Add snapshot path configuration to elasticsearch.yml
  echo -e "\n# Path to snapshots:\npath.repo: /etc/elasticsearch/snapshots" | tee -a /etc/elasticsearch/elasticsearch.yml

  # Create snapshots directory and set ownership
  mkdir -p /etc/elasticsearch/snapshots
  chown -R elasticsearch:elasticsearch /etc/elasticsearch/snapshots

  # Restart Elasticsearch service
  systemctl restart elasticsearch.service
  if ! systemctl is-active --quiet elasticsearch.service; then
    echo "Failed to restart Elasticsearch service. Exiting."
    exit 1
  fi

  # Wait for Elasticsearch to be fully up and running
  sleep 10

  # Create the snapshot repository via Elasticsearch API

  curl -s -u "$elastic_username:$elastic_password" -X PUT "http://localhost:9200/_snapshot/my_snapshot" \
    -H "Content-Type: application/json" \
    -d '{
          "type": "fs",
          "settings": {
            "location": "/etc/elasticsearch/snapshots",
            "compress": true
          }
        }' || {
    echo "Failed to create the snapshot repository."
    exit 1
  }

  echo "Snapshot repository configured successfully."
}

comment_and_replace_line() {
  local FILE=$1
  local FIND=$2
  local REPLACE=$3
  FIND_ESCAPED=$(echo "$FIND" | sed 's/[.[\*^$]/\\&/g')

  if grep -Eq "^[#]*$FIND_ESCAPED" "$FILE"; then
    sed -i.bak "/^[#]*$FIND_ESCAPED/c\\$REPLACE" "$FILE"
    print_message "Replaced '$FIND' with '$REPLACE'."
  else
    if grep -q "^#ElastiFlow PoC Configurator" "$FILE"; then
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added '$REPLACE' under '#ElastiFlow PoC Configurator'."
    else
      echo -e "\n#ElastiFlow PoC Configurator" | tee -a "$FILE" > /dev/null
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added heading and '$REPLACE'."
    fi
  fi
}

display_system_info() {
  # Main partition size in GB
  main_partition_size=$(df -h / | awk 'NR==2 {print $2}')
  echo "Main partition size: $main_partition_size"

  # Used partition space in GB
  used_partition_space=$(df -h / | awk 'NR==2 {print $3}')
  echo "Used partition space: $used_partition_space"

  # Free partition space in percentage and GB
  free_partition_space_percent=$(df -h / | awk 'NR==2 {print $5}')
  free_partition_space_gb=$(df -h / | awk 'NR==2 {print $4}')
  echo "Free partition space: $free_partition_space_gb ($free_partition_space_percent)"

  # Installed RAM in GB
  installed_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
  echo "Installed RAM: ${installed_ram_gb}GB"

  # Number of physical CPUs
  physical_cpus=$(lscpu | awk '/^Socket\(s\):/{print $2}')
  echo "Number of physical CPUs: $physical_cpus"

  # Number of physical cores per CPU
  cores_per_cpu=$(lscpu | awk '/^Core\(s\) per socket:/{print $4}')
  echo "Number of physical cores per CPU: $cores_per_cpu"

  # Total number of cores
  total_cores=$((physical_cpus * cores_per_cpu))
  echo "Total number of cores: $total_cores"
}

confirm_and_proceed() {
    printf "This script converts Ubuntu server installations to an ElastiFlow Virtual Appliance. \nPrevious installations, remnants, and information related to the following will be purged from this system: \n\n-Opensearch \n-Opensearch dashboards \n-Kibana \n-Elasticsearch \n-ElastiFlow Unified Flow Collector \n-ElastiFlow Unified SNMP Collector \n-Other related products\n\n"
    printf "Please ensure that you are only running this script on a clean, freshly installed instance of Ubuntu Server 22+ that is going to only be used for ElastiFlow.\n"
    printf "This script could be destructive to the contents or configuration of your server. \n\nProceed? (yes/no or y/n):"

    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "Proceeding with the script..."
            ;;
        [nN][oO]|[nN])
            echo "Exiting..."
            exit 1
            ;;
        *)
            echo "Invalid input. Please enter 'yes' or 'no'."
            confirm_and_proceed  # Re-prompt for valid input
            ;;
    esac
}


check_for_script_updates() {
  # Dynamically determine the path to the installed script
  local installed_script=$(realpath "$0")
  local new_script_url="https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/elasticsearch/install.sh"
  local tmp_script="/tmp/install.sh"
  print_message "Checking for installation script updates..." "$GREEN"

  echo "installed script path: $installed_script"

  wget -q -O "$tmp_script" "$new_script_url"

  if [[ $? -ne 0 ]]; then
    print_message "Failed to check for updates." "$RED"
    return
  fi

  echo "Downloaded remote script to $tmp_script."

  remote_version=$(grep -m 1 '^# Version: ' "$tmp_script" | awk '{print $3}')
  installed_version=$(grep -m 1 '^# Version: ' "$installed_script" | awk '{print $3}')

  echo "Installed script version: $installed_version"
  echo "Remote script version: $remote_version"

  if [[ -z "$installed_version" ]]; then
    print_message "Failed to detect the installed script version." "$RED"
    return
  fi

  if [[ "$remote_version" > "$installed_version" ]]; then
    print_message "Script remote version $remote_version available." "$GREEN"

    while true; do
      echo -n "Do you want to update to the Remote version of the script? (y/n) [y]: "
      for i in {10..1}; do
        echo -n "$i "
        sleep 1
      done
      echo

      read -rt 1 -n 1 update_choice
      update_choice=${update_choice:-y}

      if [[ $update_choice == "y" || $update_choice == "n" ]]; then
        break
      else
        echo "Invalid input. Please enter 'y' or 'n'."
      fi
    done

    if [[ $update_choice == "y" ]]; then
      print_message "Updating script to version $remote_version..." "$GREEN"
      cp "$tmp_script" "$installed_script"
      chmod +x "$installed_script"
      print_message "Script update successful. Restarting script..." "$GREEN"
      exec "$installed_script"
    else
      print_message "Script update skipped." "$RED"
    fi
  else
    print_message "No script updates available." "$GREEN"
  fi

  echo "Cleaning up temporary script."
  rm -f "$tmp_script"
}


get_host_ip() {
  INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(docker|lo)' | head -n 1)
  if [ -z "$INTERFACE" ]; then
    echo "No suitable network interface found."
    return 1
  else
    ip_address=$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' | cut -d/ -f1)
    if [ -z "$ip_address" ]; then
      echo "No IP address found for interface $INTERFACE."
      return 1
    else
      echo "$ip_address"
      return 0
    fi
  fi
}

download_file() {
  local url=$1
  local target_path=$2
  curl -s -o "$target_path" "$url"
  if [ $? -eq 0 ]; then
    chmod +x "$target_path"
    echo "Downloaded and made $target_path executable."
  else
    echo -e "Failed to download $target_path.\n"
  fi
}


get_dashboard_url() {
  local dashboard_id
  local kibana_url="http://$ip_address:5601"
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  case "$DATA_PLATFORM" in 
    "Elastic")
      local response=$(curl -s -u "$elastic_username:$elastic_password" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
      ;;
    "Opensearch")
      local response=$(curl -s -u "$opensearch_username:$opensearch_password" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'osd-xsrf: true')
      ;;
  esac
  dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  if [ -z "$dashboard_id" ]; then
    echo "Dashboard not found"
  else
    case "$DATA_PLATFORM" in 
    "Elastic")
      echo "$kibana_url/app/kibana#/dashboard/$dashboard_id"
      ;;
    "Opensearch")
      echo "$kibana_url/app/dashboard#/view/$dashboard_id"
      ;;
    esac
  fi
}

find_and_replace() {
  local FILE=$1
  shift
  local PAIRS=("$@")
  if [ ! -f "$FILE" ]; then
    print_message "File $FILE not found!" "$RED"
    exit 1
  fi
  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    comment_and_replace_line "$FILE" "${PAIRS[i]}" "${PAIRS[i+1]}"
  done
}

handle_error() {
  local error_msg="$1"
  local line_num="$2"
  echo "Error at line $line_num: $error_msg"
  read -rp "Do you wish to continue? (y/n):" user_decision
  if [[ $user_decision != "y" ]]; then
    echo "Exiting..."
    exit 1
  fi
}

replace_text() {
  local file_path="$1"
  local old_text="$2"
  local new_text="$3"
  local line_num="$4"
  sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}

check_for_root() {
  print_message "Checking for root..." "$GREEN"
scp 
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1

    else
      echo "Running as root." 1>&2

  fi

}

check_compatibility() {

  print_message "Checking for compatibility..." "$GREEN"

  . /etc/os-release
  ID_LOWER=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
  if [[ "$ID_LOWER" != "ubuntu" ]]; then
    echo "This script only supports Ubuntu" 1>&2
    exit 1

    else
      echo "System is compatible." 1>&2


  fi
  osversion="ubuntu"
}

sleep_message() {
  local message=$1
  local duration=$2
  printf " %s...\n" "$message"

  while [ "$duration" -gt 0 ]; do
    printf "\rTime remaining: %02d seconds" "$duration"
    sleep 1
    ((duration--))
  done

  printf "\n"
}

print_startup_message() {
  print_message "*********Setting up ElastiFlow environment...*********" "$GREEN"
}

install_prerequisites() {
  print_message "Installing prerequisites..." "$GREEN"

  echo "Updating package list..."
  apt-get -qq update > /dev/null 2>&1

  # List of packages to be installed
  packages=(jq net-tools git bc gpg default-jre curl wget apt-transport-https isc-dhcp-client libpcap-dev)

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


tune_system() {
  print_message "System tuning starting..." "$GREEN"
  kernel_tuning=$(cat <<EOF
#####ElastiFlow tuning parameters######
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
  mkdir /etc/systemd/system/elasticsearch.service.d && \
  echo -e "[Service]\nLimitNOFILE=131072\nLimitNPROC=8192\nLimitMEMLOCK=infinity\nLimitFSIZE=infinity\nLimitAS=infinity" | \
  tee /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf > /dev/null
  echo "System limits set"
  print_message "System tuning done..." "$GREEN"
}

install_elasticsearch() {
  print_message "Installing ElasticSearch...\n" "$GREEN"
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list || handle_error "Failed to add Elasticsearch repository." "${LINENO}"
  elastic_install_log=$(apt-get -q update && apt-get -q install elasticsearch=$elasticsearch_version | stdbuf -oL tee /dev/console) || handle_error "Failed to install Elasticsearch." "${LINENO}"
  #elastic_install_log=$(apt-get -q update && apt-get -q -y install elasticsearch | stdbuf -oL tee /dev/console) || handle_error "Failed to install Elasticsearch." "${LINENO}"
  elastic_initial_password=$(echo "$elastic_install_log" | awk -F' : ' '/The generated password for the elastic built-in superuser/{print $2}')
  elastic_initial_password=$(echo -n "$elastic_initial_password" | tr -cd '[:print:]')
  #printf "Elastic password: $elastic_initial_password\n"
  print_message "Configuring ElasticSearch...\n" "$GREEN"
  configure_elasticsearch
}

configure_jvm_memory() {
  print_message "Configuring JVM memory usage..." "$GREEN"
  total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  one_third_mem_gb=$(echo "$total_mem_kb / 1024 / 1024 / 3" | bc -l)
  rounded_mem_gb=$(printf "%.0f" "$one_third_mem_gb")
  if [ "$rounded_mem_gb" -gt 31 ]; then
      jvm_mem_gb=31
  else
      jvm_mem_gb=$rounded_mem_gb
  fi
  jvm_options="-Xms${jvm_mem_gb}g\n-Xmx${jvm_mem_gb}g"
  echo -e "$jvm_options" | tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null
  echo "Elasticsearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx."
}

start_elasticsearch() {
  print_message "Enabling and starting ElasticSearch service..." "$GREEN"
  systemctl daemon-reload && systemctl enable elasticsearch.service && systemctl start elasticsearch.service
  sleep_message "Giving ElasticSearch service time to stabilize" 10
  print_message "Checking if Elastic service is running..." "$GREEN"
  if systemctl is-active --quiet elasticsearch.service; then
    printf "Elasticsearch service is running.\n"
  else
    echo "Elasticsearch is not running.\n"
  fi
  print_message "Checking if Elastic server is up..." "$GREEN"
  curl_result=$(curl -s -k -u $elastic_username:"$elastic_initial_password" https://localhost:9200)
  search_text='cluster_name" : "elasticsearch'
  if echo "$curl_result" | grep -q "$search_text"; then
      echo -e "Elastic is up! Used authenticated curl.\n"
  else
    echo -e "Something's wrong with Elastic...\n"
  fi
}

install_kibana() {
  echo -e "Downloading and installing Kibana...\n"
  apt-get -q update && apt-get -q install kibana=$kibana_version
  #apt-get -q update && apt-get -q -y install kibana

}

configure_kibana() {
  print_message "Configuring Kibana..." "$GREEN"
  echo -e "Generating Kibana saved objects encryption key...\n"
  output=$(/usr/share/kibana/bin/kibana-encryption-keys generate -q)
  key_line=$(echo "$output" | grep '^xpack.encryptedSavedObjects.encryptionKey')
  if [[ -n "$key_line" ]]; then
      echo "$key_line" | tee -a /etc/kibana/kibana.yml > /dev/null
  else
      echo "No encryption key line found."
  fi

  echo -e "Generating Kibana enrollment token...\n"
  kibana_token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
  echo -e "Kibana enrollment token is:\n$kibana_token\n"
  echo -e "Enrolling Kibana with Elastic...\n"
  /usr/share/kibana/bin/kibana-setup --enrollment-token "$kibana_token"
  echo -e "Enabling and starting Kibana service...\n"
  systemctl daemon-reload && systemctl enable kibana.service && systemctl start kibana.service
  sleep_message "Giving Kibana service time to stabilize" 20
  
  echo -e "Configuring Kibana - set 0.0.0.0 as server.host\n"
  replace_text "/etc/kibana/kibana.yml" "#server.host: \"localhost\"" "server.host: \"0.0.0.0\"" "${LINENO}"

  echo -e "Configuring Kibana - Replacing any other instances of the current IP with 0.0.0.0\n"
  replace_text "/etc/kibana/kibana.yml" "$ip_address" "0.0.0.0" "${LINENO}"

  echo -e "Configuring Kibana - set elasticsearch.hosts to localhost instead of interface IP...\n"
  replace_text "/etc/kibana/kibana.yml" "elasticsearch.hosts: \['https:\/\/[^']*'\]" "elasticsearch.hosts: \['https:\/\/localhost:9200'\]" "${LINENO}"
  
  echo -e "Configuring Kibana - Stopping Kibana from complaining about missing base url\n"
  replace_text "/etc/kibana/kibana.yml" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"

  echo -e "Configuring Kibana - Help with Kibana complaining during long running queries\n"
  replace_text "/etc/kibana/kibana.yml" "#unifiedSearch.autocomplete.valueSuggestions.timeout: 1000" "unifiedSearch.autocomplete.valueSuggestions.timeout: 4000" "${LINENO}"
  replace_text "/etc/kibana/kibana.yml" "#unifiedSearch.autocomplete.valueSuggestions.terminateAfter: 100000" "unifiedSearch.autocomplete.valueSuggestions.terminateAfter: 100000" "${LINENO}"

  echo -e "Configuring Kibana - Disabling Kibana / Elastic telemetry\n"
  echo "telemetry.optIn: false" >> /etc/kibana/kibana.yml
  echo "telemetry.enabled: false" >> /etc/kibana/kibana.yml

  echo -e "Configuring Kibana - Enabling PNG and PDF report generation...\n"
  echo -e '\nxpack.reporting.capture.browser.chromium.disableSandbox: true\nxpack.reporting.queue.timeout: 120000\nxpack.reporting.capture.timeouts:\n  openUrl: 30000\n  renderComplete: 30000\n  waitForElements: 30000' >> /etc/kibana/kibana.yml
  systemctl daemon-reload
  systemctl restart kibana.service
  sleep_message "Giving Kibana service time to stabilize" 20

}

change_elasticsearch_password() {
  print_message "Changing Elastic password to $elastic_password...\n"
  curl -k -X POST -u "$elastic_username:$elastic_initial_password" "https://localhost:9200/_security/user/elastic/_password" -H 'Content-Type: application/json' -d"
  {
    \"password\": \"$elastic_password\"
  }"
  elastic_initial_password=$elastic_password
}

install_elastiflow() {
  case "$DATA_PLATFORM" in 
    "Elastic")
      elastiflow_config_strings=(
      "EF_LICENSE_KEY" "EF_LICENSE_KEY: '${ef_license_key}'"
      "EF_LICENSE_FLOW_RECORDS_PER_SECOND" "EF_LICENSE_FLOW_RECORDS_PER_SECOND: $frps"
      "EF_LICENSE_ACCEPTED" "EF_LICENSE_ACCEPTED: 'true'"
      "EF_ACCOUNT_ID" "EF_ACCOUNT_ID: '${ef_account_id}'"
      "EF_OUTPUT_ELASTICSEARCH_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ENABLE: 'true'"
      "EF_OUTPUT_ELASTICSEARCH_ADDRESSES" "EF_OUTPUT_ELASTICSEARCH_ADDRESSES: '127.0.0.1:9200'"
      "EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE: '${ecs_enable}'"
      "EF_OUTPUT_ELASTICSEARCH_PASSWORD" "EF_OUTPUT_ELASTICSEARCH_PASSWORD: '${elastic_password}'"
      "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE: 'true'"
      "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION" "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION: 'true'"
      "EF_FLOW_SERVER_UDP_IP" "EF_FLOW_SERVER_UDP_IP: '0.0.0.0'"
      "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE" "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE: '33554432'"
      "EF_PROCESSOR_DECODE_IPFIX_ENABLE" "EF_PROCESSOR_DECODE_IPFIX_ENABLE: 'true'"
      "EF_LOGGER_FILE_LOG_ENABLE" "EF_LOGGER_FILE_LOG_ENABLE: 'true'"
      "EF_LOGGER_FILE_LOG_FILENAME" "EF_LOGGER_FILE_LOG_FILENAME: '/var/log/elastiflow/flowcoll/flowcoll.log'"
      "EF_OUTPUT_ELASTICSEARCH_TSDS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_TSDS_ENABLE: '${elastic_tsds}'"
      "EF_PROCESSOR_ENRICH_IPADDR_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_METADATA_USERDEF_PATH" "EF_PROCESSOR_ENRICH_IPADDR_METADATA_USERDEF_PATH: '/etc/elastiflow/metadata/ipaddrs.yml'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_USERDEF_PATH" "EF_PROCESSOR_ENRICH_NETIF_METADATA_USERDEF_PATH: '/etc/elastiflow/metadata/netifs.yml'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_USERDEF_PATH" "EF_PROCESSOR_ENRICH_IPADDR_DNS_USERDEF_PATH: '/etc/elastiflow/hostname/user_defined.yml'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_INCLEXCL_PATH" "EF_PROCESSOR_ENRICH_IPADDR_DNS_INCLEXCL_PATH: '/etc/elastiflow/hostname/incl_excl.yml'"
      "EF_PROCESSOR_ENRICH_APP_ID_ENABLE" "EF_PROCESSOR_ENRICH_APP_ID_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_APP_ID_PATH" "EF_PROCESSOR_ENRICH_APP_ID_PATH: '/etc/elastiflow/app/appid.yml'"
      "EF_PROCESSOR_ENRICH_APP_IPPORT_ENABLE" "EF_PROCESSOR_ENRICH_APP_IPPORT_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_APP_IPPORT_PATH" "EF_PROCESSOR_ENRICH_APP_IPPORT_PATH: '/etc/elastiflow/app/ipport.yml'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_TIMEOUT" "EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_TIMEOUT: '60'"
      "EF_OUTPUT_ELASTICSEARCH_INDEX_TEMPLATE_REPLICAS" "EF_OUTPUT_ELASTICSEARCH_INDEX_TEMPLATE_REPLICAS: 0"
      )
      ;;
    "Opensearch")
      elastiflow_config_strings=(
      "EF_LICENSE_KEY" "EF_LICENSE_KEY: '${ef_license_key}'"
      "EF_LICENSE_FLOW_RECORDS_PER_SECOND" "EF_LICENSE_FLOW_RECORDS_PER_SECOND: $frps"
      "EF_LICENSE_ACCEPTED" "EF_LICENSE_ACCEPTED: 'true'"
      "EF_ACCOUNT_ID" "EF_ACCOUNT_ID: '${ef_account_id}'"
      "EF_OUTPUT_ELASTICSEARCH_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ENABLE: 'false'"
      "EF_OUTPUT_OPENSEARCH_ENABLE" "EF_OUTPUT_OPENSEARCH_ENABLE: 'true'"
      "EF_OUTPUT_OPENSEARCH_ADDRESSES" "EF_OUTPUT_OPENSEARCH_ADDRESSES: '127.0.0.1:9200'"
      "EF_OUTPUT_OPENSEARCH_ECS_ENABLE" "EF_OUTPUT_OPENSEARCH_ECS_ENABLE: '${ecs_enable}'" 
      "EF_OUTPUT_OPENSEARCH_USERNAME" "EF_OUTPUT_OPENSEARCH_USERNAME: 'admin'"
      "EF_OUTPUT_OPENSEARCH_PASSWORD" "EF_OUTPUT_OPENSEARCH_PASSWORD: '${opensearch_password}'"
      "EF_OUTPUT_OPENSEARCH_TLS_ENABLE" "EF_OUTPUT_OPENSEARCH_TLS_ENABLE: 'true'"
      "EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION" "EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION: 'true'"
      "EF_FLOW_SERVER_UDP_IP" "EF_FLOW_SERVER_UDP_IP: '0.0.0.0'"
      "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE" "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE: '33554432'"
      "EF_PROCESSOR_DECODE_IPFIX_ENABLE" "EF_PROCESSOR_DECODE_IPFIX_ENABLE: 'true'"
      "EF_LOGGER_FILE_LOG_ENABLE" "EF_LOGGER_FILE_LOG_ENABLE: 'true'"
      "EF_LOGGER_FILE_LOG_FILENAME" "EF_LOGGER_FILE_LOG_FILENAME: '/var/log/elastiflow/flowcoll/flowcoll.log'"
      "EF_PROCESSOR_ENRICH_IPADDR_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_METADATA_USERDEF_PATH" "EF_PROCESSOR_ENRICH_IPADDR_METADATA_USERDEF_PATH: '/etc/elastiflow/metadata/ipaddrs.yml'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_USERDEF_PATH" "EF_PROCESSOR_ENRICH_NETIF_METADATA_USERDEF_PATH: '/etc/elastiflow/metadata/netifs.yml'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_USERDEF_PATH" "EF_PROCESSOR_ENRICH_IPADDR_DNS_USERDEF_PATH: '/etc/elastiflow/hostname/user_defined.yml'"
      "EF_PROCESSOR_ENRICH_IPADDR_DNS_INCLEXCL_PATH" "EF_PROCESSOR_ENRICH_IPADDR_DNS_INCLEXCL_PATH: '/etc/elastiflow/hostname/incl_excl.yml'"
      "EF_PROCESSOR_ENRICH_APP_ID_ENABLE" "EF_PROCESSOR_ENRICH_APP_ID_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_APP_ID_PATH" "EF_PROCESSOR_ENRICH_APP_ID_PATH: '/etc/elastiflow/app/appid.yml'"
      "EF_PROCESSOR_ENRICH_APP_IPPORT_ENABLE" "EF_PROCESSOR_ENRICH_APP_IPPORT_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_APP_IPPORT_PATH" "EF_PROCESSOR_ENRICH_APP_IPPORT_PATH: '/etc/elastiflow/app/ipport.yml'"
      "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE" "EF_PROCESSOR_ENRICH_NETIF_METADATA_ENABLE: 'true'"
      "EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_TIMEOUT" "EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_TIMEOUT: '60'"
      "EF_OUTPUT_ELASTICSEARCH_INDEX_TEMPLATE_REPLICAS" "EF_OUTPUT_ELASTICSEARCH_INDEX_TEMPLATE_REPLICAS: 0"
      )
      ;;
    esac

  print_message "\nDownloading and installing ElastiFlow Flow Collector..." "$GREEN"
  #wget -O flow-collector_"$flowcoll_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$flowcoll_version"_linux_amd64.deb
  #apt-get -q install ./flow-collector_"$flowcoll_version"_linux_amd64.deb
  #change_elasticsearch_password

  install_latest_elastiflow_flow_collector

  print_message "Configuring ElastiFlow Flow Collector..." "$GREEN"
  find_and_replace "$flowcoll_config_path" "${elastiflow_config_strings[@]}"
  replace_text "/etc/systemd/system/flowcoll.service" "TimeoutStopSec=infinity" "TimeoutStopSec=60" "N/A"
  print_message "Enabling and starting ElastiFlow service..." "$GREEN"
  systemctl daemon-reload && systemctl enable flowcoll.service && systemctl start flowcoll.service
  sleep_message "Giving ElastiFlow service time to stabilize" 10
}

install_kibana_dashboards() {
  print_message "Downloading and installing ElastiFlow flow dashboards..." "$GREEN"
  git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/

  response=$(curl --connect-timeout 10 -X POST -u $elastic_username:$elastic_initial_password "localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" --form file=@/etc/elastiflow_for_elasticsearch/kibana/flow/kibana-$flow_dashboards_version-flow-$flow_dashboards_codex_ecs.ndjson -H 'kbn-xsrf: true')

  if [ $? -ne 0 ]; then
    printf "Error: %s\n" "$response"
    printf "Flow dashboards not installed successfully\n"
  else
    dashboards_success=$(echo "$response" | jq -r '.success')
    if [ "$dashboards_success" == "true" ]; then
        printf "Flow dashboards installed successfully.\n"
    else
        printf "Flow dashboards not installed successfully\n"
    fi
  fi
}

install_osd_dashboards() {
  print_message "Downloading and installing ElastiFlow flow dashboards..." "$GREEN"
  git clone https://github.com/elastiflow/elastiflow_for_opensearch.git /etc/elastiflow_for_opensearch/

  #create tenants using opensearch documented REST API
  curl -k -XPUT -H'content-type: application/json' https://"$opensearch_username:$opensearch_password"@localhost:9200/_plugins/_security/api/tenants/elastiflow -d '{"description": "ElastiFLow Dashboards"}'
  

  #login to opensearch-dashboards and save the cookie.
  curl -k -XGET -u "$opensearch_username:$opensearch_password" -c dashboards_cookie http://localhost:5601/api/login/
  curl -k -XGET -b dashboards_cookie http://localhost:5601/api/v1/configuration/account | jq

  #switch tenant. note the tenant is kept inside the cookie so we need to save it after this request
  curl -k -XPOST -b dashboards_cookie -c dashboards_cookie -H'osd-xsrf: true' -H'content-type: application/json' http://localhost:5601/api/v1/multitenancy/tenant -d '{"tenant": "elastiflow", "username": "admin"}'
  curl -k -XGET -b dashboards_cookie http://localhost:5601/api/v1/configuration/account | jq

  #push the dashboard using the same cookie
  response=$(curl -k -XPOST -H'osd-xsrf: true' -b dashboards_cookie http://localhost:5601/api/saved_objects/_import?overwrite=true --form file=@/etc/elastiflow_for_opensearch/dashboards/flow/dashboards-$osd_flow_dashboards_version-flow-$flow_dashboards_codex_ecs.ndjson)
  # response=$(curl --connect-timeout 10 -X POST -u $opensearch_username:$opensearch_password "localhost:5601/api/saved_objects/_import?overwrite=true" -H "osd-xsrf: true" --form file=@/etc/elastiflow_for_opensearch/dashboards/flow/dashboards-$osd_flow_dashboards_version-flow-$flow_dashboards_codex_ecs.ndjson -H 'osd-xsrf: true')

  if [ $? -ne 0 ]; then
    printf "Error: %s\n" "$response"
    printf "Flow dashboards not installed successfully\n"
  else
    dashboards_success=$(echo "$response" | jq -r '.success')
    if [ "$dashboards_success" == "true" ]; then
        printf "Flow dashboards installed successfully.\n"
    else
        printf "Flow dashboards not installed successfully\n"
    fi
  fi
}

configure_elasticsearch() {

  config_strings=(
  "indices.query.bool.max_clause_count" "indices.query.bool.max_clause_count: 8192"
  "search.max_buckets" "search.max_buckets: 250000"
  )

  find_and_replace "/etc/elasticsearch/elasticsearch.yml" "${config_strings[@]}"
}

check_service_status() {
  local SERVICE_NAME=$1
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    print_message "$SERVICE_NAME is up" "$GREEN"
  else
    print_message "$SERVICE_NAME is not up" "$RED"
  fi
}

resize_part_to_max() {
    # Display the partition size before resizing
    print_message "Resizing partition to max." "$GREEN"
    echo "Partition size before resizing:"
    lsblk -o NAME,SIZE | grep 'ubuntu-lv'
    # Extend the logical volume to use all free space
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

    # Resize the filesystem
    resize2fs -p /dev/mapper/ubuntu--vg-ubuntu--lv
}


check_all_services() {
  case "$DATA_PLATFORM" in 
    "Elastic")
      SERVICES=("elasticsearch.service" "kibana.service" "flowcoll.service")
      ;;
    "Opensearch")
      SERVICES=("opensearch.service" "opensearch-dashboards.service" "flowcoll.service")
      ;;
  esac
  for SERVICE_NAME in "${SERVICES[@]}"; do
      check_service_status "$SERVICE_NAME"
  done
}

check_dashboards_status() {
  if [ "$dashboards_success" == "true" ]; then
       print_message "Dashboards are installed ✓" "$GREEN"
  else
       print_message "Dashboards are not installed X" "$RED"
  fi
}

display_info() {
  print_message "Installation summary" "$GREEN"

  version=$(/usr/share/elastiflow/bin/flowcoll -version)
  echo -e "Installed ElastiFlow Flow version: $version"
  version=$flow_dashboards_version
  echo -e "Installed ElastiFlow Flow Dashboards version: $flow_dashboards_codex_ecs $version"
  case "$DATA_PLATFORM" in 
    "Elastic")
      version=$(/usr/share/kibana/bin/kibana --version --allow-root | jq -r '.config.serviceVersion.value' 2>/dev/null)
      echo -e "Installed Kibana version: $version\n"
      version=$(/usr/share/elasticsearch/bin/elasticsearch --version | grep -oP 'Version: \K[\d.]+')
      echo -e "Installed Elasticsearch version: $version"
      ;;
    "Opensearch")
      version=$(grep -oP 'version: \K[\d.]+' /usr/share/opensearch-dashboards/manifest.yml )
      echo -e "Installed Opensearch Dashboards version: $version\n"
      version=$(/usr/share/opensearch/bin/opensearch --version | grep -oP 'Version: \K[\d.]+')
      echo -e "Installed Opensearch version: $version"
      ;;
  esac

  version=$(java -version 2>&1)
  echo -e "Installed Java version: $version"
  version=$(lsb_release -d | awk -F'\t' '{print $2}')
  echo -e "Operating System: $version"
  display_system_info

}

display_dashboard_url() {
  dashboard_url=$(get_dashboard_url "ElastiFlow (flow): Overview")
  case "$DATA_PLATFORM" in 
    "Elastic")
      printf "*********************************************\n"
      printf "\033[32m\nGo to %s (%s / %s)\n\033[0m" "$dashboard_url" "$elastic_username" "$elastic_password"
      printf "DO NOT CHANGE THIS PASSWORD VIA KIBANA. ONLY CHANGE IT VIA sudo ./configure\n"
      printf "For further configuration options, run sudo ./configure\n"
      printf "*********************************************\n"
      ;;
    "Opensearch")
      printf "*********************************************\n"
      printf "\033[32m\nGo to %s (%s / %s)\n\033[0m" "$dashboard_url" "$opensearch_username" "$opensearch_password"
      printf "DO NOT CHANGE THIS PASSWORD VIA OPENSEARCH DASHBOARDS. ONLY CHANGE IT VIA sudo ./configure\n"
      printf "For further configuration options, run sudo ./configure\n"
      printf "*********************************************\n"
      ;;
  esac
}
remove_update_service(){
  print_message "Removing Ubuntu update service...\n"
  apt-get remove -y unattended-upgrades
}

append_to_bashrc() {
    local text="$1"
    # Append the text to .bashrc
    echo "$text" >> /home/user/.bashrc
    echo "The script has been added to .bashrc."

    # Reload the .bashrc file
    . /home/user/.bashrc
    echo ".bashrc has been reloaded."
}

cleanup (){
  installed_script=$(realpath "$0")
  #release DHCP address
  dhclient -r

  rm /etc/update-motd.d/*

  #delete self and any deb files
  rm -f "$installed_script"
  rm -f *.deb

  clean_system_junk

}

download_aux_files() {
  local current_dir="$(pwd)"
  download_file "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/ElastiFlow_Virtual_Appliance_Builder/configure/configure.sh" "$current_dir/configure.sh"
}


set_kibana_homepage() {
  local dashboard_id
  local kibana_url="http://$ip_address:5601"
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')

  print_message "Setting homepage to ElastiFlow dashboard..." "$GREEN"

  # Fetch the dashboard ID
  local find_response=$(curl -s -u "$elastic_username:$elastic_password" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
  dashboard_id=$(echo "$find_response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')

  if [ -z "$dashboard_id" ]; then
    echo "Dashboard ID $dashboard_id not found. Cannot set homepage.\n"
  else
    local payload="{\"changes\":{\"defaultRoute\":\"/app/dashboards#/view/${dashboard_id}\"}}"

    # Update the default route
    local update_response=$(curl -s -o /dev/null -w "%{http_code}" -u "$elastic_username:$elastic_password" \
      -X POST "$kibana_url/api/kibana/settings" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "$payload")

    if [[ "$update_response" -ne 200 ]]; then
      echo "Failed to set home as \"$dashboard_title\".\n"
      else
        echo "Home page successfully set to \"$dashboard_title\""
        echo "--> $kibana_url/app/kibana#/dashboard/$dashboard_id"
      fi
  fi
}

install_latest_elastiflow_flow_collector() {
    local DOC_URL="https://docs.elastiflow.com/docs/flowcoll/install_linux"

    echo "Scraping $DOC_URL for download details..."

    # Function to validate a URL
    validate_url() {
        if curl --output /dev/null --silent --head --fail "$1"; then
            echo "$1"
        else
            echo ""
        fi
    }

    # Scrape and validate the first valid URL for the .deb file
    local DEB_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb' | head -n 1)
    DEB_URL=$(validate_url "$DEB_URL")

    # Scrape and validate the first valid URL for the .sha256 checksum file
    local SHA256_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sha256' | head -n 1)
    SHA256_URL=$(validate_url "$SHA256_URL")

    # Scrape and validate the first valid URL for the GPG signature file (.deb.sig)
    local GPG_SIG_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sig' | head -n 1)
    GPG_SIG_URL=$(validate_url "$GPG_SIG_URL")

    # Scrape for the GPG key ID
    local GPG_KEY_ID=$(curl -sL $DOC_URL | grep -oP 'class="token plain">echo &quot;\K[A-F0-9]{40}' | head -n 1)

    # Scrape and validate the URL for the public key (.pgp)
    local GPG_PUBKEY_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+elastiflow\.pgp' | head -n 1)
    GPG_PUBKEY_URL=$(validate_url "$GPG_PUBKEY_URL")

    # Check if the DEB_URL was found and is valid
    if [ -z "$DEB_URL" ]; then
        echo "Error: Could not find a valid .deb file URL in $DOC_URL."
        exit 1
    fi

    echo "Found DEB URL: $DEB_URL"
    echo "Found SHA256 URL: $SHA256_URL"
    echo "Found GPG Signature URL: $GPG_SIG_URL"
    echo "Found GPG Key ID: $GPG_KEY_ID"
    echo "Found GPG public key URL: $GPG_PUBKEY_URL"


    # Extract the filename from the URL
    local FILENAME=$(basename "$DEB_URL")

    # Extract the version number from the filename
    local REMOTE_VERSION=$(echo "$FILENAME" | grep -oP 'flow-collector_\K[0-9]+\.[0-9]+\.[0-9]+')

    # Check the currently installed version of ElastiFlow
    local CURRENT_VERSION=$(/usr/share/elastiflow/bin/flowcoll -version 2>/dev/null || echo "None")

    echo "Current installed version: ${CURRENT_VERSION}"
    echo "Remote version: $REMOTE_VERSION"

    # Download all files to /tmp
    local DOWNLOAD_DIR="/tmp"
    # Extract the filename from the URL and combine it with the download directory path
    local DEB_FILE="$DOWNLOAD_DIR/$FILENAME"
    echo "DEB file will be downloaded to: $DEB_FILE"

    # Download the .deb file
    wget -O "$DEB_FILE" "$DEB_URL" || {
        echo "Error: Failed to download .deb file."
        exit 1
    }

    # Attempt to download the checksum file
    if [ -n "$SHA256_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$SHA256_URL" || {
            echo "Warning: Failed to download checksum file."
            read -p "Do you want to continue without checksum verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            SHA256_URL=""
        }
    fi

    # Attempt to download the GPG signature file
    if [ -n "$GPG_SIG_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" "$GPG_SIG_URL" || {
            echo "Warning: Failed to download GPG signature file."
            read -p "Do you want to continue without GPG signature verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            GPG_SIG_URL=""
        }
    fi


# Attempt to download the GPG public key file
if [ -n "$GPG_PUBKEY_URL" ]; then
    GPG_PUBKEY_FILE="$DOWNLOAD_DIR/$(basename $GPG_PUBKEY_URL)"
    wget -O "$GPG_PUBKEY_FILE" "$GPG_PUBKEY_URL" || {
        echo "Warning: Failed to download GPG public key file."
        read -p "Do you want to continue without the GPG public key? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Installation aborted by user."
            exit 1
        fi
        GPG_PUBKEY_URL=""
    }
fi

# Import GPG public key
if [ -n "$GPG_PUBKEY_FILE" ] && [ -f "$GPG_PUBKEY_FILE" ]; then
    echo "Importing GPG public key..."
    gpg --import "$GPG_PUBKEY_FILE" || {
        echo "Warning: Failed to import GPG public key."
        read -p "Do you want to continue without importing the GPG public key? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Installation aborted by user."
            exit 1
        fi
    }
else
    echo "No GPG public key file found. Skipping GPG key import."
fi

    # Import and trust the GPG key
    if [ -n "$GPG_KEY_ID" ]; then
        echo "Importing and trusting the GPG key..."
        echo "$GPG_KEY_ID:6:" | gpg --import-ownertrust || {
            echo "Warning: Failed to import GPG key."
            read -p "Do you want to continue without GPG key import? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
        }

    else
        echo "No GPG key ID found. Skipping GPG key import."
    fi

    # Verify the checksum if the checksum file was downloaded
    if [ -n "$SHA256_URL" ]; then
        echo "Verifying checksum..."
        local ACTUAL_CHECKSUM=$(sha256sum $DEB_FILE | awk '{print $1}')
        local EXPECTED_CHECKSUM=$(cat "$DOWNLOAD_DIR/$(basename $SHA256_URL)" | awk '{print $1}')
        if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            echo "Error: Checksum verification failed."
            rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)"
            exit 1
        else
            echo "Checksum verification passed."
        fi
    else
        echo "Skipping checksum verification."
    fi

    # Verify the GPG signature if the signature file was downloaded
    if [ -n "$GPG_SIG_URL" ]; then
        echo "Verifying GPG signature..."
        gpg --verify "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" $DEB_FILE || {
            echo "Warning: GPG verification failed. Continuing without GPG verification."
        }
        echo "GPG verification passed."
    else
        echo "No GPG signature file found. Skipping GPG verification."
    fi

    # Install the .deb package using apt
    echo "Installing the downloaded .deb file using apt-get..."
    apt-get -qq install -y $DEB_FILE || {
        echo "Error: Failed to install $DEB_FILE."
        exit 1
    }

    # Clean up the downloaded files
    echo "Cleaning up..."
    rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)"

    echo "ElastiFlow Installation completed successfully."
}

pick_search_engine() {
  options=(
      "Elasticsearch + Kibana"
      "Opensearch + Opensearch Dashboards"
      "Exit Install script"
  )

  # Function to display options
  display_options() {
      echo "Please select which search engine to imstall:"
      for i in "${!options[@]}"; do
          echo "$((i + 1)). ${options[i]}"
      done
  }

  # Prompt the user for input
  while true; do
      display_options
      read -rp "Enter the number corresponding to your choice: " choice

      # Validate the input
      if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
          echo "You selected: ${options[choice - 1]}"
          break
      else
          echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
      fi
  done

  # Perform actions based on the user's choice
  case "$choice" in
      1)
          echo "Starting the process..."
          ;;
      2)
          echo "Checking the status..."
          ;;
      3)
          echo "Exiting..."
          exit 0
          ;;
  esac
}

install_opensearch() {
  print_message "Installing Opensearch...\n" "$GREEN"
  curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring || handle_error "Failed to add Opensearch GPG key." "${LINENO}"
  echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-2.x.list || handle_error "Failed to add Opensearch repository." "${LINENO}"
  opensearch_install_log=$(apt-get -q update &&  env OPENSEARCH_INITIAL_ADMIN_PASSWORD=$opensearch_password apt-get install opensearch=$opensearch_version | stdbuf -oL tee /dev/console) || handle_error "Failed to install Opensearch." "${LINENO}"
  print_message "Configuring Opensearch...\n" "$GREEN"
  configure_opensearch
}

start_opensearch() {
  print_message "Enabling and starting Opensearch service..." "$GREEN"
  systemctl daemon-reload && systemctl enable opensearch.service && systemctl start opensearch.service
  sleep_message "Giving Opensearch service time to stabilize" 10
  print_message "Checking if Opensearch service is running..." "$GREEN"
  if systemctl is-active --quiet opensearch.service; then
    printf "Opensearch service is running.\n"
  else
    echo "Opensearch is not running.\n"
  fi
  print_message "Checking if Opensearch server is up..." "$GREEN"
  curl_result=$(curl -s -k -u $opensearch_username:"$opensearch_password" https://localhost:9200)
  search_text='cluster_name" : "opensearch'
  if echo "$curl_result" | grep -q "$search_text"; then
      echo -e "Opensearch is up! Used authenticated curl.\n"
  else
    echo -e "Something's wrong with Opensearch...\n"
  fi
}

configure_opensearch() {

  config_strings=(
  "indices.query.bool.max_clause_count" "indices.query.bool.max_clause_count: 8192"
  "search.max_buckets" "search.max_buckets: 250000"
  )

  find_and_replace "/etc/opensearch/opensearch.yml" "${config_strings[@]}" || handle_error "File etc/opensearch/opensearch.yml not found " "${LINENO}"
}

install_opensearch_dashboards() {
  echo -e "Downloading and installing Opensearch Dashboards...\n"
  echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-dashboards-2.x.list || handle_error "Failed to add Opensearch-dashboards repository." "${LINENO}"
  apt-get -q update && apt-get -q install opensearch-dashboards=$opensearch_version
}

configure_opensearch_dashboards() {
#   echo -e "Generating Opensearch Dashboards saved objects encryption key...\n"
#   output=$(/usr/share/kibana/bin/kibana-encryption-keys generate -q)
#   key_line=$(echo "$output" | grep '^xpack.encryptedSavedObjects.encryptionKey')
#   if [[ -n "$key_line" ]]; then
#       echo "$key_line" | tee -a /etc/opensearch-dashboards/opensearch_dashboards.yml > /dev/null
#   else
#       echo "No encryption key line found."
#   fi

  echo -e "Enabling and starting Opensearch Dashboards service...\n"
  systemctl daemon-reload && systemctl enable opensearch-dashboards.service && systemctl start opensearch-dashboards.service
  sleep_message "Giving Opensearch Dashboards service time to stabilize" 20
  echo -e "Configuring Opensearch Dashboards - set 0.0.0.0 as server.host\n"
  replace_text "/etc/opensearch-dashboards/opensearch_dashboards.yml" "# server.host: \"localhost\"" "server.host: \"0.0.0.0\"" "${LINENO}"
  echo -e "Configuring Opensearch Dashboards - set opensearch.hosts to localhost instead of interface IP...\n"
  replace_text "/etc/opensearch-dashboards/opensearch_dashboards.yml" "opensearch.hosts: \['https:\/\/[^']*'\]" "opensearch.hosts: \['https:\/\/localhost:9200'\]" "${LINENO}"
  replace_text "/etc/opensearch-dashboards/opensearch_dashboards.yml" "opensearch.username: kibanaserver" "opensearch.username: admin" "${LINENO}"
  replace_text "/etc/opensearch-dashboards/opensearch_dashboards.yml" "opensearch.password: kibanaserver" "opensearch.password: $opensearch_password" "${LINENO}"
  systemctl daemon-reload
  systemctl restart opensearch-dashboards.service
  sleep_message "Giving Opensearch Dashboards service time to stabilize" 20

}

install_data_platform() {
  case "$DATA_PLATFORM" in 
    "Elastic")
      install_elasticsearch
      configure_jvm_memory
      start_elasticsearch
      ;;
    "Opensearch")
      install_opensearch
      configure_jvm_memory
      start_opensearch
      ;;
  esac
}

install_data_playtform_ui() {
  case "$DATA_PLATFORM" in 
    "Elastic")
      install_kibana
      configure_kibana
      change_elasticsearch_password
      ;;
    "Opensearch")
      install_opensearch_dashboards
      configure_opensearch_dashboards
      ;;
  esac
}

 install_dashboards() {
  case "$DATA_PLATFORM" in 
    "Elastic")
      install_kibana_dashboards
      set_kibana_homepage "ElastiFlow (flow): Overview"
      ;;
    "Opensearch")
      install_osd_dashboards
      ;;
  esac
 }

main() {
  check_for_script_updates
  confirm_and_proceed
  select_search_engine
  print_startup_message
  check_for_root
  sanitize_system
  check_compatibility
  disable_predictable_network_names
  install_os_updates
  ip_address=$(get_host_ip)
  remove_update_service
  disable_swap_if_swapfile_in_use
  install_prerequisites
  tune_system
  sleep_message "Giving dpkg time to clean up" 10
  install_data_platform
  sleep_message "Giving dpkg time to clean up" 10
  install_data_playtform_ui
  install_elastiflow
  install_dashboards
  download_aux_files
  check_all_services
  check_dashboards_status
  resize_part_to_max
  display_info
  display_dashboard_url
  create_banner
  cleanup
  print_message "**************************" "$GREEN"
  print_message "All done" "$GREEN"
  print_message "Access the GUI via http://$ip_address:5601" "$GREEN"
  print_message "**************************" "$GREEN"
  
  }

main
