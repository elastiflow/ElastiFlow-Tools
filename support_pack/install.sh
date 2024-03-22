#!/bin/bash

# Prepare environment
current_time=$(date "+%Y%m%d%H%M%S")
archive_name="Elastiflow_Support_Pack_$current_time.tar.gz"
log_file="script_execution.log"
system_info_file="system.txt"

# Initialize log file
echo "Starting script execution at $(date)" > $log_file

# Copy directories and files
echo "Copying directories and files..." | tee -a $log_file
cp -r /etc/elastiflow . 2>>$log_file || echo "/etc/elastiflow not found, skipping..." >> $log_file
cp /etc/kibana/kibana.yml . 2>>$log_file || echo "/etc/kibana/kibana.yml not found, skipping..." >> $log_file
cp /var/log/kibana/kibana.log . 2>>$log_file || echo "/var/log/kibana/kibana.log not found, skipping..." >> $log_file
cp /etc/elasticsearch/elasticsearch.yml . 2>>$log_file || echo "/etc/elasticsearch/elasticsearch.yml not found, skipping..." >> $log_file
cp /var/log/elasticsearch/elasticsearch.log . 2>>$log_file || echo "/var/log/elasticsearch/elasticsearch.log not found, skipping..." >> $log_file
cp /etc/systemd/system/flowcoll.service.d/flowcoll.conf . 2>>$log_file || echo "/etc/systemd/system/flowcoll.service.d/flowcoll.conf not found, skipping..." >> $log_file
cp /etc/systemd/system/flowcoll.service . 2>>$log_file || echo "/etc/systemd/system/flowcoll.service not found, skipping..." >> $log_file
cp /var/log/elastiflow/flowcoll/flowcoll.log . 2>>$log_file || echo "/var/log/elastiflow/flowcoll/flowcoll.log not found, skipping..." >> $log_file
cp /etc/systemd/system/snmpcoll.service.d/snmpcoll.conf . 2>>$log_file || echo "/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf not found, skipping..." >> $log_file
cp /etc/systemd/system/snmpcoll.service . 2>>$log_file || echo "/etc/systemd/system/snmpcoll.service not found, skipping..." >> $log_file
cp /var/log/elastiflow/snmpcoll/snmpcoll.log . 2>>$log_file || echo "/var/log/elastiflow/snmpcoll/snmpcoll.log not found, skipping..." >> $log_file

# Capture system information
echo "Capturing system information..." | tee -a $log_file
{
  echo "Date and Time: $(date)"
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
} > $system_info_file

# Create the archive
echo "Creating archive..." | tee -a $log_file
tar -czf $archive_name . --exclude=$archive_name --exclude=$log_file 2>>$log_file
echo "Archive created: $archive_name" | tee -a $log_file

# Append the archive creation to log and include the log into the archive
echo "Finalizing archive with log file..." >> $log_file
tar -rzf $archive_name $log_file --remove-files 2>>$log_file

# Output final details
files_count=$(tar -tzf $archive_name | wc -l)
echo "Number of files archived: $files_count" | tee -a $log_file
full_path=$(realpath $archive_name)
echo "Full path of the archive: $full_path" | tee -a $log_file
