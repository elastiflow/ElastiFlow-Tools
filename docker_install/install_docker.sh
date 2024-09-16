
#!/bin/bash

    
# Add Docker's official GPG key
apt-get update
apt-get install -y ca-certificates curl > /dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -qq > /dev/null
apt-get install -qq -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
   
# Verify that Docker is installed
if docker --version > /dev/null 2>&1; then
   echo "Docker installation was successful."
else
   echo "Docker installation failed."
fi
