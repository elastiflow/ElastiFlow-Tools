#!/bin/bash

# Setup
current_time=$(date "+%Y%m%d%H%M%S")

hostname=$(hostname)
archive_name="elastiflow_support_pack_${hostname}_$current_time.tar.gz"

log_file="script_execution.log"
system_info_file="system.txt"
temp_dir="temp_elastiflow_$current_time"

# Create temporary directory
mkdir -p $temp_dir

# Initialize log file
exec &> >(tee -a "$temp_dir/$log_file") # Capture all output to log file

check_port_9200_usage() {
    if nc -z localhost 9200; then
        echo "Port 9200 is in use."
        return 1
    else
        echo "Port 9200 is not in use. Elasticsearch might not be running."
        return 0
    fi
}

attempt_fetch() {
    local ip=$1
    local username=$2
    local password=$3

    # Attempt to fetch node stats
    response=$(curl -sk -u "$username:$password" "https://$ip:9200/_nodes/stats/indices?pretty")

    echo "$response" | grep "cluster_name" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Successfully fetched node stats."
        echo "$response" > $tempdir/node_stats.txt # Save the successful response to "node_stats.txt"
        return 0
    else
        echo "Failed to fetch node stats."
        return 1
    fi
}

prompt_credentials_and_fetch() {
    read -p "Would you like to obtain node stats? (y/n): " confirm
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
"/etc/systemd/system/elasticsearch.service.d/elasticsearch.conf"
"/var/log/elasticsearch/elasticsearch.log"

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
for path in "${paths[@]}"; do
    if [[ -d $path ]]; then
        # It's a directory, check its size first
        dir_size=$(du -sm "$path" | cut -f1) # Get size in MB
        if [[ $dir_size -gt 50 ]]; then
            echo "$path is larger than 50MB, skipping..."
            continue # Skip this directory
        fi

        # If the directory is not larger than 50MB, copy everything
        cp -r "$path" "$temp_dir" 2>/dev/null || echo "$path not found, skipping..."
    else
        # It's a file, check if it's a log file by its path
        if [[ $path == *.log ]]; then
            # It's a log file, copy only the first 1 MB
            dd if="$path" of="$temp_dir/$(basename "$path")" bs=1M count=1 2>/dev/null || echo "$path not found, skipping..."
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

  
} > "$temp_dir/$system_info_file"

# Create the archive
echo "Creating archive..."
tar -czf $archive_name -C $temp_dir . 2>/dev/null
echo "Archive created: $archive_name"

# Output final details
files_count=$(tar -tzf $archive_name | wc -l)
echo "Number of files archived: $files_count"
full_path=$(realpath $archive_name)
echo -e "\033[32mPlease send this file to ElastiFlow:\n$full_path\033[0m"
# Output the archive size using ls
archive_size=$(ls -l "$archive_name" | awk '{print $5}')
echo "Archive size: $archive_size bytes"

# Clean up
echo "Cleaning up..."
rm -rf $temp_dir

echo "Done."
