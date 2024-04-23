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

# Step 2: Remove SSH keys
echo "Removing SSH keys..."
rm -f /etc/ssh/ssh_host_*

# Step 3: Clear user command history
echo "Clearing user command histories..."
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        rm -f $user_home/.bash_history
        rm -f $user_home/.zsh_history
        # You can add other shell history files to clean
    fi
done

# Clear root user history
rm -f /root/.bash_history
rm -f /root/.zsh_history
rm -f /user/.bash_history
rm -f /user/.zsh_history
history -c

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
