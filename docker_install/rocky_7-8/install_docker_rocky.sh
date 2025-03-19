#!/bin/bash

# ----- Only allow Rocky Linux -----
if [ ! -f /etc/os-release ]; then
  echo "Unable to detect OS. This script only works on Rocky Linux."
  exit 1
fi

. /etc/os-release

if [ "$ID" != "rocky" ]; then
  echo "Unsupported OS. This script only works on Rocky Linux."
  exit 1
fi
# ----------------------------------

# Install dependencies
echo "Installing required packages..."
dnf -y install yum-utils ca-certificates curl

# Add Docker's repository (CentOS-based repo works on Rocky)
echo "Adding Docker's official repository..."
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker packages
echo "Installing Docker packages..."
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
echo "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

# Verify Docker is installed and running
if docker --version &> /dev/null; then
  echo "Docker installation was successful."
  echo "Docker version: $(docker --version)"
else
  echo "Docker installation failed."
  exit 1
fi

echo "Script completed successfully."
