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

check_port_9200_usage() {
    if nc -z localhost 9200; then
        echo "I think I found Elasticsearch. Port 9200 is in use."
        return 1
    else
        echo "Port 9200 is not in use. Elasticsearch / Opensearch might not be running or is on a different machine."
        return 0
    fi
}


attempt_fetch() {
    local ip=$1
    local username=$2
    local password=$3

    # Attempt to fetch node stats
    response=$(curl -sk -u "$username:$password" "https://$ip:9200/_nodes/stats/os,process,indices?pretty")
    echo "$response" | grep "cluster_name" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Successfully fetched node stats."
        echo "$response" > "$temp_dir/node_stats.txt" # Save the successful response to "node_stats.txt"
        return 0
    else
        echo "Failed to fetch node stats."
        return 1
    fi
}

prompt_credentials_and_fetch() {
    read -p "Would you like to obtain node stats? (y by default): " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        echo "User chose not to obtain node stats. Continuing with the rest of the script."
        return 0
    fi

    while true; do
        read -p "Enter Elasticsearch IP address or host (localhost by default): " ip
        ip=${ip:-localhost}

        read -p "Enter your Elasticsearch username: " username
        read -s -p "Enter your Elasticsearch password: " password
        echo

        if attempt_fetch "$ip" "$username" "$password"; then
            return 0
        fi

        read -t 10 -p "Attempt failed. Do you want to retry? (y/n): " retry
       if [[ $? -gt 128 ]]; then
            echo -e "\nTimeout reached. Continuing with the rest of the script."
            return 1
        elif [[ $retry =~ ^[Nn]$ ]]; then
            echo "User chose not to retry. Continuing with the rest of the script."
            return 1
        fi
    done  
}


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
"/etc/opensearch/opensearch.yml"
"/etc/opensearch/jvm.options.d/heap.options"
"/var/log/opensearch/opensearch.log"
"/etc/systemd/system/opensearch.service.d/opensearch.conf"

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
check_port_9200_usage
port_usage=$?

if [ $port_usage -eq 1 ]; then
    echo "Proceeding since port 9200 is in use."
    prompt_credentials_and_fetch
else
    echo "Exiting since Elasticsearch might not be running."
    exit 1
fi


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
