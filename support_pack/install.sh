#!/bin/bash

# Define the current date and time format
current_date=$(date +"%Y-%m-%d_%H%M%S")

# Define the archive name and the log file name
archive_name="elastiflow_support_pack_$current_date.tar.gz"
log_file="script_execution_$current_date.log"

# Start logging
exec > >(tee "$log_file") 2>&1

# List of directories and files to archive
items_to_archive=(
  "/etc/elastiflow"
  "/etc/kibana/kibana.yml"
  "/etc/elasticsearch/elasticsearch.yml"
  "/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
  "/etc/systemd/system/flowcoll.service"
  "/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf"
  "/etc/systemd/system/snmpcoll.service"
  "/var/log/elastiflow/flowcoll/flowcoll.log"
  "/var/log/elastiflow/snmpcoll/snmpcoll.log"
  "/var/log/elasticsearch/elasticsearch.log"
  "/var/log/kibana/kibana.log"

)

# Temporary directory for files that exist
temp_dir=$(mktemp -d)

# Check each item and copy it to the temp directory if it exists
for item in "${items_to_archive[@]}"; do
  if [ -e "$item" ]; then
    # Use --parents to preserve directory structure
    cp -a --parents "$item" "$temp_dir"
  else
    echo "Warning: $item does not exist and will be skipped."
  fi
done

# Move to the temp directory
cd "$temp_dir"

# Archive and compress the items
tar -czf "$archive_name" *

# Move the archive to the original working directory
mv "$archive_name" "$OLDPWD"

# Move back to the original directory
cd "$OLDPWD"

# Cleanup the temporary directory
rm -rf "$temp_dir"

# Count the number of files archived
num_files=$(tar -tzf "$archive_name" | wc -l)

# Display the details
echo "Number of files archived: $num_files"
echo "Full path of the archive: $(pwd)/$archive_name"

# Append the log details to the log file
echo "Number of files archived: $num_files" >> "$log_file"
echo "Full path of the archive: $(pwd)/$archive_name" >> "$log_file"

# Final message
echo "Elastiflow support pack created"
