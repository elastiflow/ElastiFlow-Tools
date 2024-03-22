#!/bin/bash

# Setup
current_time=$(date "+%Y%m%d%H%M%S")
archive_name="Elastiflow_Support_Pack_$current_time.tar.gz"
log_file="script_execution.log"
system_info_file="system.txt"
temp_dir="temp_elastiflow_$current_time"

# Create temporary directory
mkdir -p $temp_dir

# Initialize log file
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>"$temp_dir/$log_file" 2>&1 # Capture all output to log file

echo "Starting script execution at $(date)"

# Array of paths to copy
declare -a paths=(
"/etc/elastiflow"
"/etc/kibana/kibana.yml"
"/var/log/kibana/kibana.log"
"/etc/elasticsearch/elasticsearch.yml"
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
echo "Capturing system information..."
{
  echo "Date and Time: $(date)"
  echo "Operating System Version:"
  uname -a
  echo "ElastiFlow Version:"
  /usr/share/elastiflow/bin/flowcoll -version 2>/dev/null || echo "ElastiFlow version information not available"
  echo "SNMP Collector Version:"
  /usr/share/elastiflow/bin/snmpcoll -version 2>/dev/null || echo "SNMP Collector version information not available"
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

# Calculate the size of the archive
archive_size=$(du -sh $archive_name | cut -f1)
echo "Archive size: $archive_size"

# Output final details
files_count=$(tar -tzf $archive_name | wc -l)
echo "Number of files archived: $files_count"
full_path=$(realpath $archive_name)
echo "Full path of the archive: $full_path"

# Clean up
echo "Cleaning up..."
rm -rf $temp_dir
# Ensure script execution log file is also deleted after being archived
rm -f "$temp_dir/$log_file"

echo "Script execution completed."
