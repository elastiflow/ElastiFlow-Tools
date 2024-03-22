
#!/bin/bash

# Setup the date format for the filename
current_date=$(date +"%Y-%m-%d_%H%M%S")

# Define the destination filename
destination_file="Elastiflow_Support_Pack_$current_date.tar.gz"

# Define the log file name
log_file="script_execution_log.txt"

# Start logging
echo "Starting the execution of the script at $(date)" > "$log_file"
echo "Attempting to copy and archive the following files:" >> "$log_file"

# Files to be copied and archived
files=(
  "/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
  "/etc/elastiflow/flowcoll.yml"
  "/etc/systemd/system/flowcoll.service"
  "/var/log/elastiflow/flowcoll/flowcoll.log"
  "/etc/systemd/system/snmpcoll.service.d/snmpcoll.conf"
  "/etc/elastiflow/snmpcoll.yml"
  "/etc/systemd/system/snmpcoll.service"
  "/var/log/elastiflow/snmpcoll/snmpcoll.log"
)

# Create a temporary directory for the files
temp_dir=$(mktemp -d)

# Copy files to the temporary directory if they exist
for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "Copying: $file" >> "$log_file"
    cp --parents "$file" "$temp_dir"
  else
    echo "File does not exist, skipping: $file" >> "$log_file"
  fi
done

# Move the log file to the temporary directory
mv "$log_file" "$temp_dir"

# Change to the temporary directory
cd "$temp_dir"

# Create the tar.gz archive, including the log file
tar -czf "$destination_file" *

# Move the archive back to the original directory
mv "$destination_file" "$OLDPWD"

# Clean up by removing the temporary directory
cd "$OLDPWD"
rm -rf "$temp_dir"

echo "Elastiflow support pack created: $destination_file"
echo "Log of the execution is included in the archive."
