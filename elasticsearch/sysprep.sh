#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Step 1: Clean up temp directories
echo "Cleaning up temp directories..."
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /home/user/*


# Clear root user history
rm -f /root/.bash_history
rm -f /root/.zsh_history
rm -f /user/.bash_history
rm -f /user/.zsh_history

# Iterate over each user's home directory
for user_home in /home/*; do
  # Check if the .bash_history file exists and delete it
  if [ -f "$user_home/.bash_history" ]; then
    echo "Clearing history for $(basename $user_home)"
    > "$user_home/.bash_history"  # This empties the file without deleting it
  fi
done

# Step 4: Clean apt cache
echo "Cleaning apt cache..."
apt-get clean

# Step 5: Truncate logs
echo "Truncating logs..."
find /var/log -type f -exec truncate -s 0 {} \;

# Step 6: Remove old kernels (optional)
echo "Removing old kernels..."
apt-get autoremove --purge

# Step 7: Zero out free space to reduce image size (optional)
#echo "Zeroing free space to reduce image size... This might take a while."
#dd if=/dev/zero of=/bigemptyfile bs=1M
#rm -f /bigemptyfile

# Completion
echo "Cleanup complete. System ready for imaging."
