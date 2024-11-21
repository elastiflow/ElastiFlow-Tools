#!/bin/bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker

# Verify that Docker is installed
if docker --version > /dev/null 2>&1; then
   echo "Docker installation was successful."
else
   echo "Docker installation failed."
fi
