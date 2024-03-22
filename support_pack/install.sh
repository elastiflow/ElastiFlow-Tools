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

echo "Starting script execution at $(date)"

# Array of paths to copy
declare -a paths=(
#dir
"/etc/elastiflow"
#dir
"/etc/sysctl.d"
#files
"/etc/sysctl.conf"

"/etc/kibana/kibana.yml"
"/var/log/kibana/kibana.log"
"/etc/systemd/system/kibana.service.d/kibana.conf"

"/etc/elasticsearch/elasticsearch.yml"
"/etc/systemd/system/elasticsearch.service.d/elasticsearch.conf"
"/var/log/elasticsearch/elasticsearch.log"

"/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
"/etc/systemd/system/flowcoll.service"
"/var/log/elastiflow/flowcoll/flowcoll.log"

"/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf"
"/etc/systemd/system/snmpcoll.service"
"/var/log/elastiflow/snmpcoll/snmpcoll.log"
)

# Copy files to temporary directory
echo "Copying directories and files..."
for path in "${paths[@]}"; do
    cp -r $path $temp_dir 2>/dev/null || echo "$path not found, skipping..."
done

# Capture system information
{
  echo "Date and Time: $(date)"
  echo "Operating System Version:"
  uname -a
  echo "ElastiFlow Version:"
  /usr/share/elastiflow/bin/flowcoll -version 2>/dev/null || echo "ElastiFlow version information not available"
  echo "SNMP Collector Version:"
  /usr/share/elastiflow/bin/snmpcoll -version 2>/dev/null || echo "SNMP Collector version information not available"
  echo "Elasticsearch Version:"
  /usr/share/elasticsearch/bin/elasticsearch -version
  echo "Kibana Version:"
  /usr/share/kibana/bin/kibana -version
  echo "Running Processes:"
  ps -aux
  echo "Services:"
  systemctl list-unit-files --type=service | grep enabled
  echo "Network Configuration:"
  ip addr
  echo "Disk Space Usage:"
  df -h
  echo "Memory Usage:"
  free -m
} > "$temp_dir/$system_info_file"

# Create the archive
echo "Creating archive..."
tar -czf $archive_name -C $temp_dir . 2>/dev/null
echo "Archive created: $archive_name"

# Output final details
files_count=$(tar -tzf $archive_name | wc -l)
echo "Number of files archived: $files_count"
full_path=$(realpath $archive_name)
echo -e "\033[32mSend this to ElastiFlow: $full_path\033[0m"

# Clean up
echo "Cleaning up..."
rm -rf $temp_dir

echo "Done."
