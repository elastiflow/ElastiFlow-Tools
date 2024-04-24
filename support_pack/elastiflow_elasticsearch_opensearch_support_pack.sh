#!/bin/bash

# version 1.5
# author: O.J. Wolanyk, ElastiFlow



# Setup
current_time=$(date "+%Y%m%d%H%M%S")

hostname=$(hostname)
archive_name="elastiflow_support_pack_${hostname}_$current_time.tar.gz"

log_file="script_execution.log"
system_info_file="system.txt"
temp_dir="temp_elastiflow_$current_time"

# Create temporary directory
mkdir -p $temp_dir

attempt_fetch() {
    local retry_choice
    local default_ip="localhost"
    local default_port=9200
    local default_username="elastic"
    local default_password="elastic"

    while true; do
        # Prompt user for inputs with defaults
        read -p "Enter IP address [$default_ip]: " ip
        ip=${ip:-$default_ip}

        read -p "Enter port [$default_port]: " port
        port=${port:-$default_port}

        read -p "Enter username [$default_username]: " username
        username=${username:-$default_username}

        read -p "Enter password [$default_password]: " password
        password=${password:-$default_password}

        # Attempt to fetch node stats
        response=$(curl -sk -u "$username:$password" "https://$ip:$port/_nodes/stats/os,process,indices?pretty")
        echo "$response" | grep "cluster_name" &> /dev/null
        if [ $? -eq 0 ]; then
            echo "Successfully fetched node stats."
            mkdir -p "$temp_dir"  # Ensure temp directory exists
            echo "$response" > "$temp_dir/node_stats.txt" # Save the successful response to "node_stats.txt"
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
}



# Function to get hardware information
get_hardware_info() {
    # Print system information
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "Kernel Version: $(uname -r)"
    echo "Operating System: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d '"' -f 2)"
    echo

    # Print CPU information
    echo "=== CPU Information ==="
    lscpu
    echo

    # Print memory information
    echo "=== Memory Information ==="
    free -h
    echo

    # Print disk information
    echo "=== Disk Information ==="
    df -h
    echo

    # Print PCI devices information
    echo "=== PCI Devices Information ==="
    lspci
    echo

    # Print USB devices information
    echo "=== USB Devices Information ==="
    lsusb
    echo

    # Print network interfaces information
    echo "=== Network Interfaces Information ==="
    ip addr
    echo

    # Print installed software packages
    echo "=== Installed Software Packages ==="
    dpkg -l
}

# Initialize log file
exec &> >(tee -a "$temp_dir/$log_file") # Capture all output to log file


echo "Starting ElastiFlow Support Pack at $(date)"


# Array of paths to copy
declare -a paths=(
#dir
"/etc/elastiflow"
#dir
"/etc/sysctl.d"
#files
"/etc/sysctl.conf"

# Kibana config
"/etc/kibana/kibana.yml"
"/var/log/kibana/kibana.log"

# Elasticsearch config
"/etc/elasticsearch/elasticsearch.yml"
"/etc/elasticsearch/jvm.options.d/heap.options"
"/etc/systemd/system/elasticsearch.service.d/elasticsearch.conf"
"/var/log/elasticsearch/elasticsearch.log"

# OpenSearch config
#ubuntu
"/etc/opensearch/opensearch.yml"
"/etc/opensearch/jvm.options"
"/var/log/opensearch/opensearch.log"
"/etc/systemd/system/opensearch.service.d/opensearch.conf"
"/usr/share/opensearch-dashboards/config/opensearch_dashboards.yml"

#debian
"/usr/lib/sysctl.d/opensearch.conf"

# flowcoll
"/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
"/etc/systemd/system/flowcoll.service"
"/var/log/elastiflow/flowcoll/flowcoll.log"

# snmpcoll
"/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf"
"/etc/systemd/system/snmpcoll.service"
"/var/log/elastiflow/snmpcoll/snmpcoll.log"
)

# Copy files to temporary directory
echo "Copying directories and files..."

# Function to check if a file is binary
is_binary() {
    # Use the 'file' command to check if the file is binary
    if file "$1" | grep -q "text"; then
        return 1 # Not binary
    else
        return 0 # Binary
    fi
}

# Loop through each path
for path in "${paths[@]}"; do
    if [[ -d $path ]]; then
        # It's a directory, check its size first
        dir_size=0 # Initialize directory size
        # Loop through files in the directory
        while IFS= read -r -d '' file; do
            if is_binary "$file"; then
                continue # Skip binary files
            fi
            # Add the size of non-binary files to the directory size
            dir_size=$(( dir_size + $(stat -c '%s' "$file") / 1024 / 1024 )) # Size in MB
        done < <(find "$path" -type f -print0)
        
        if [[ $dir_size -gt 100 ]]; then
            echo "$path is larger than 100MB, skipping..."
            continue # Skip this directory
        fi

        # If the directory is not larger than 50MB, copy everything
        cp -r "$path" "$temp_dir" 2>/dev/null || echo "$path not found, skipping..."
    else
        # It's a file, check if it's a log file by its path
        if [[ $path == *.log ]]; then
            # It's a log file, copy only the last 1 MB
            tail -c $(( 1024*1024 )) "$path" > "$temp_dir/$(basename "$path")"
        else
            # Not a log file, copy normally
            cp "$path" "$temp_dir" 2>/dev/null || echo "$path not found, skipping..."
        fi
    fi
done

####obtain node stats...
attempt_fetch


# Capture system information
{
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
  /usr/share/elasticsearch/bin/elasticsearch -version
 
  echo "----------------------------------------------"
  echo "Kibana Version:"
  /usr/share/kibana/bin/kibana -version
  
  echo "----------------------------------------------"
  echo "Opensearch Version:"
  /usr/share/opensearch/bin/opensearch -version
  
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

  get_hardware_info

  
} > "$temp_dir/$system_info_file"

# Create the archive
echo "Creating archive..."
tar -czf $archive_name -C $temp_dir . 2>/dev/null
echo "Archive created: $archive_name"

# Output final details
files_count=$(tar -tzf $archive_name | wc -l)
echo "Number of files archived: $files_count"

# Output the archive size using ls
archive_size=$(ls -l "$archive_name" | awk '{print $5}')
echo "Archive size: $archive_size bytes"

full_path=$(realpath $archive_name)
echo -e "\033[32mPlease send this file to ElastiFlow:\n$full_path\033[0m"

# Clean up
echo "Cleaning up..."
rm -rf $temp_dir

echo "Done."
