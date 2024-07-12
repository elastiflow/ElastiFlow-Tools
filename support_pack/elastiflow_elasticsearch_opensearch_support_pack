#!/bin/bash

# Version: 2.0
# author: O.J. Wolanyk, ElastiFlow

# Setup
current_time=$(date "+%Y%m%d%H%M%S")
hostname=$(hostname)
archive_name="elastiflow_support_pack_${hostname}_$current_time.tar.gz"
log_file="script_execution.log"
system_info_file="system.txt"
temp_dir="temp_elastiflow_$current_time"

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create temporary directory
mkdir -p $temp_dir

print_message() {
  local message=$1
  local color=$2
  echo -e "${color}${message}${NC}"
}

check_for_updates() {
  # Dynamically determine the path to the current script
  local current_script=$(realpath "$0")
  local new_script_url="https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/support_pack/elastiflow_elasticsearch_opensearch_support_pack"
  local tmp_script="/tmp/configure"

  echo "Checking for updates..."
  echo "Current script path: $current_script"

  wget -q -O "$tmp_script" "$new_script_url"

  if [[ $? -ne 0 ]]; then
    print_message "Failed to check for updates." "$RED"
    return
  fi

  echo "Downloaded new script to $tmp_script."

  local new_version=$(grep -m 1 '^# Version: ' "$tmp_script" | awk '{print $3}')
  local current_version=$(grep -m 1 '^# Version: ' "$current_script" | awk '{print $3}')

  echo "Current version: $current_version"
  echo "Remote version: $new_version"

  if [[ -z "$current_version" ]]; then
    print_message "Failed to detect the current version." "$RED"
    return
  fi

  if [[ "$new_version" > "$current_version" ]]; then
    print_message "Remote version $new_version available." "$GREEN"
    
    while true; do
      echo -n "Do you want to update to the Remote version? (y/n) [y]: "
      for i in {10..1}; do
        echo -n "$i "
        sleep 1
      done
      echo
      
      read -t 1 -n 1 update_choice
      update_choice=${update_choice:-y}
      
      if [[ $update_choice == "y" || $update_choice == "n" ]]; then
        break
      else
        echo "Invalid input. Please enter 'y' or 'n'."
      fi
    done

    if [[ $update_choice == "y" ]]; then
      print_message "Updating to version $new_version..." "$GREEN"
      cp "$tmp_script" "$current_script"
      chmod +x "$current_script"
      print_message "Update successful. Restarting script..." "$GREEN"
      exec "$current_script"
    else
      print_message "Update skipped." "$RED"
    fi
  else
    print_message "No updates available." "$GREEN"
  fi

  echo "Cleaning up temporary script."
  rm -f "$tmp_script"
}





# Function to get the last 200 lines of logs for specified services
get_service_logs() {
    local services=("elasticsearch.service" "kibana.service" "flowcoll.service" "snmpcoll.service")
    
    for service in "${services[@]}"; do
        local log_file="journalctl_${service}"
        echo "Fetching logs for $service..."
        if journalctl -n 200 -u "$service" > "$temp_dir/$log_file" 2>/dev/null; then
            echo "Successfully fetched logs for $service."
        else
            echo "Failed to fetch logs for $service or service does not exist. Continuing..."
        fi
    done
}

attempt_fetch_node_stats() {
    local retry_choice
    local fetch_choice
    local default_ip="localhost"
    local default_port=9200
    local default_username="elastic"
    local default_password="elastic"

    read -p "Do you want to obtain node stats? (yes/no) " fetch_choice
    case $fetch_choice in
        [Yy]* )
            while true; do
                read -p "Enter IP address [$default_ip]: " ip
                ip=${ip:-$default_ip}
                read -p "Enter port [$default_port]: " port
                port=${port:-$default_port}
                read -p "Enter username [$default_username]: " username
                username=${username:-$default_username}
                read -p "Enter password [$default_password]: " password
                password=${password:-$default_password}

                response=$(curl -sk -u "$username:$password" "https://$ip:$port/_nodes/stats/os,process,indices?pretty")
                if echo "$response" | grep -q "cluster_name"; then
                    echo "Successfully fetched node stats."
                    echo "$response" > "$temp_dir/node_stats.txt"
                    return 0
                else
                    echo "Failed to fetch node stats."
                    read -p "Do you want to retry? (yes/no) " retry_choice
                    case $retry_choice in
                        [Yy]* ) continue;;
                        * ) echo "Exiting without success."; return 1;;
                    esac
                fi
            done
            ;;
        * )
            echo "Exiting without attempting to fetch node stats."
            return 1
            ;;
    esac
}

check_and_enable_flowcoll_logging() {
    local file="/etc/elastiflow/flowcoll.yml"
    local key_value="EF_LOGGER_FILE_LOG_ENABLE: \"true\""

    if grep -q "$key_value" "$file" && ! grep -q "^#.*$key_value" "$file"; then
        echo "Key-value pair $key_value already exists and is uncommented in $file."
    else
        echo "Key-value pair $key_value does not exist or is commented out in $file."
        read -p "Would you like to add it? (yes/no): " response
        if [[ $response =~ ^[Yy] ]]; then
            echo "$key_value" | sudo tee -a "$file"
            echo "Added $key_value to $file."

            read -p "Would you like to reload the daemon and restart the flowcoll service? (yes/no): " reload_response
            if [[ $reload_response =~ ^[Yy] ]]; then
                echo "Reloading daemon and restarting flowcoll service..."
                sudo systemctl daemon-reload
                sudo systemctl restart flowcoll
                echo "Daemon reloaded and flowcoll service restarted."
            else
                echo "Daemon reload and flowcoll service restart skipped."
            fi
        else
            echo "No changes made."
        fi
    fi
}

attempt_fetch_saved_objects() {
    local retry_choice
    local share_choice
    local default_protocol="http"
    local default_ip="localhost"
    local default_port=5601
    local default_username="elastic"
    local default_password="elastic"

    read -p "Do you want to share dashboards? (yes/no) " share_choice
    case $share_choice in
        [Yy]* )
            while true; do
                read -p "Enter protocol (http/https) [$default_protocol]: " protocol
                protocol=${protocol:-$default_protocol}
                read -p "Enter IP address [$default_ip]: " ip
                ip=${ip:-$default_ip}
                read -p "Enter port [$default_port]: " port
                port=${port:-$default_port}
                read -p "Enter username [$default_username]: " username
                username=${username:-$default_username}
                read -s -p "Enter password [$default_password]: " password
                password=${password:-$default_password}
                echo

                response=$(curl -sk -u "$username:$password" "$protocol://$ip:$port/api/status")
                if echo "$response" | jq -e '.name' &> /dev/null; then
                    echo "Successfully connected to Kibana."
                    KIBANA_URL="$protocol://$ip:$port"
                    USERNAME="$username"
                    PASSWORD="$password"
                    backup_saved_objects
                    return 0
                else
                    echo "Failed to connect to Kibana."
                    read -p "Do you want to retry? (yes/no) " retry_choice
                    case $retry_choice in
                        [Yy]* ) continue;;
                        * ) echo "Exiting without success."; return 1;;
                    esac
                fi
            done
            ;;
        * )
            echo "Exiting without attempting to share dashboards."
            return 1
            ;;
    esac
}

backup_saved_objects() {
    local OUTPUT_FILE="kibana_saved_objects_backup.ndjson"
    echo "Exporting all saved objects of specific types..."
    curl -s -u "$USERNAME:$PASSWORD" -X POST "$KIBANA_URL/api/saved_objects/_export" -H "kbn-xsrf: true" -H "Content-Type: application/json" -d '{
      "type": ["dashboard", "visualization", "search", "index-pattern", "map", "lens"],
      "includeReferencesDeep": true
    }' --output "$OUTPUT_FILE"

    if [ $? -eq 0 ]; then
        echo "All saved objects successfully backed up to $OUTPUT_FILE"
        cp "$OUTPUT_FILE" "$temp_dir/$OUTPUT_FILE"
    else
        echo "Failed to back up saved objects."
    fi
}

get_system_info() {
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "Kernel Version: $(uname -r)"
    echo "Operating System: $(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2)"
    echo

    echo "=== CPU Information ==="
    lscpu
    echo

    echo "=== Memory Information ==="
    free -h
    echo

    echo "=== Disk Information ==="
    df -h
    echo

    echo "=== PCI Devices Information ==="
    lspci
    echo

    echo "=== USB Devices Information ==="
    lsusb
    echo

    echo "=== Network Interfaces Information ==="
    ip addr
    echo

    echo "=== Installed Software Packages ==="
    dpkg -l
    rpm -qa

    echo "----------------------------------------------"
    echo "Date and Time: $(date)"

    echo "----------------------------------------------"
    echo "Operating System Version:"
    uname -a

    echo "----------------------------------------------"
    echo "ElastiFlow Flow Collector Version:"
    /usr/share/elastiflow/bin/flowcoll -version 2>/dev/null || echo "ElastiFlow version information not available"

    echo "----------------------------------------------"
    echo "ElastiFlow SNMP Collector Version:"
    /usr/share/elastiflow/bin/snmpcoll -version 2>/dev/null || echo "SNMP Collector version information not available"

    echo "----------------------------------------------"
    echo "Elasticsearch Version:"
    /usr/share/elasticsearch/bin/elasticsearch -version 2>/dev/null || echo "ElasticSearch version information not available"

    echo "----------------------------------------------"
    echo "Kibana Version:"
    /usr/share/kibana/bin/kibana -version 2>/dev/null || echo "Kibana version information not available"

    echo "----------------------------------------------"
    echo "Opensearch Version:"
    /usr/share/opensearch/bin/opensearch -version 2>/dev/null || echo "Opensearch version information not available"

    echo "----------------------------------------------"
    echo "Open ports:"
    ss -tulpn | grep LISTEN

    echo "----------------------------------------------"
    echo "Running Processes:"
    ps -aux

    echo "----------------------------------------------"
    echo "Services:"
    systemctl list-unit-files --type=service | grep enabled

    echo "----------------------------------------------"
    echo "Network Configuration:"
    ip addr

    echo "----------------------------------------------"
    echo "Disk Space Usage:"
    df -h

    echo "----------------------------------------------"
    echo "Memory Usage:"
    free -m
    echo "----------------------------------------------"
}

backup_configs() {
    declare -a paths=(
        "/etc/elastiflow"
        "/etc/sysctl.d"
        "/etc/sysctl.conf"
        "/etc/kibana/kibana.yml"
        "/var/log/kibana/kibana.log"
        "/etc/elasticsearch/elasticsearch.yml"
        "/etc/elasticsearch/jvm.options.d/heap.options"
        "/etc/systemd/system/elasticsearch.service.d/elasticsearch.conf"
        "/var/log/elasticsearch/elasticsearch.log"
        "/etc/opensearch/opensearch.yml"
        "/etc/opensearch/jvm.options"
        "/var/log/opensearch/opensearch.log"
        "/etc/systemd/system/opensearch.service.d/opensearch.conf"
        "/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml"
        "/usr/lib/sysctl.d/opensearch.conf"
        "/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
        "/etc/systemd/system/flowcoll.service"
        "/var/log/elastiflow/flowcoll/flowcoll.log"
        "/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf"
        "/etc/systemd/system/snmpcoll.service"
        "/var/log/elastiflow/snmpcoll/snmpcoll.log"
    )

    echo "Copying directories and files..."

    for path in "${paths[@]}"; do
        if [[ ! -e $path ]]; then
            echo -e "\033[0;31m$path does not exist, skipping...\033[0m"
            continue
        fi

        if [[ -d $path ]]; then
            find "$path" -type f ! -name "*.mmdb" -exec cp --parents {} "$temp_dir" \; 2>/dev/null && echo -e "\033[0;32mSuccessfully copied $path to $temp_dir\033[0m"
        else
            if [[ $path == *.log ]]; then
                tail -c $(( 1024 * 1024 )) "$path" > "$temp_dir/$(basename "$path")" && echo -e "\033[0;32mSuccessfully copied last 1MB of $path to $temp_dir\033[0m"
            else
                cp "$path" "$temp_dir" 2>/dev/null && echo -e "\033[0;32mSuccessfully copied $path to $temp_dir\033[0m"
            fi
        fi
    done
}

wrap_up() {
    echo "Creating archive..."
    tar -czf $archive_name -C $temp_dir . 2>/dev/null
    echo "Archive created: $archive_name"

    files_count=$(tar -tzf $archive_name | wc -l)
    echo "Number of files archived: $files_count"

    archive_size=$(ls -l "$archive_name" | awk '{print $5}')
    echo "Archive size: $archive_size bytes"

    full_path=$(realpath $archive_name)
    echo -e "\033[32mPlease send this file to ElastiFlow:\n$full_path\033[0m"

    echo "Cleaning up..."
    rm -rf $temp_dir

    echo "Done."
}

exec &> >(tee -a "$temp_dir/$log_file")

echo "Starting ElastiFlow Support Pack at $(date)"
check_for_updates
check_and_enable_flowcoll_logging
attempt_fetch_node_stats
attempt_fetch_saved_objects
get_system_info > "$temp_dir/$system_info_file"
backup_configs
get_service_logs
wrap_up
