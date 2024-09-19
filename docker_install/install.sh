#!/bin/bash

# Function to check if the user is root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

# Function to ask the user if they want to deploy Elastiflow
ask_deploy() {
  while true; do
    read -p "Do you want to deploy Elastiflow? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying Elastiflow."
        exit 0
        ;;
      *)
        echo "Please answer y/yes or n/no."
        ;;
    esac
  done
}

# Function to download the required files (overwriting existing files)
download_files() {
  SCRIPT_DIR="$(dirname "$(realpath "$0")")"
  INSTALL_DIR="$SCRIPT_DIR/elastiflow_install"
  
  # Create the directory if it doesn't exist
  mkdir -p "$INSTALL_DIR"
  
  # Download files (force overwrite existing files)
  echo "Downloading files to $INSTALL_DIR..."
  curl -L -o "$INSTALL_DIR/.env" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env"
  curl -L -o "$INSTALL_DIR/elasticsearch_kibana_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml"
  curl -L -o "$INSTALL_DIR/elastiflow_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_compose.yml"
  curl -L -o "$INSTALL_DIR/install_docker.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install_docker.sh"
  curl -L -o "$INSTALL_DIR/readme.md" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/readme.md"
}

# Function to edit the .env file after downloading
edit_env_file() {
  ENV_FILE="$INSTALL_DIR/.env"
  if command -v nano &> /dev/null; then
    nano "$ENV_FILE"
  else
    vi "$ENV_FILE"
  fi
}

# Function to check if Docker is installed and install if necessary
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    chmod +x "$INSTALL_DIR/install_docker.sh"
    bash "$INSTALL_DIR/install_docker.sh"

    # Verify if Docker is installed after running the install script
    if ! command -v docker &> /dev/null; then
      echo "Docker installation failed. Please check the installation process and try again."
      exit 1
    fi
  else
    echo "Docker is already installed."
  fi
}

tune_system() {
printf "\n\n\n*********System tuning starting...\n\n"
kernel_tuning=$(cat <<EOF
#####ElastiFlow tuning parameters######
#For light to moderate ingest rates (less than 75000 flows per second: https://docs.elastiflow.com/docs/flowcoll/requirements/
net.core.netdev_max_backlog=4096
net.core.rmem_default=262144
net.core.rmem_max=67108864
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_mem=2097152 4194304 8388608
vm.max_map_count=262144
#######################################
EOF
  )
  sed -i '/net.core.netdev_max_backlog=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_default=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_max=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_rmem_min=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_mem=/s/^/#/' /etc/sysctl.conf
  sed -i '/vm.max_map_count=/s/^/#/' /etc/sysctl.conf
  echo "$kernel_tuning" >> /etc/sysctl.conf
  sysctl -p
  echo "Kernel parameters updated in /etc/sysctl.conf with previous configurations commented out."
  printf "\n\n\n*********System tuning done...\n\n"
}


# Function to deploy Elastiflow using Docker Compose
deploy_elastiflow() {
  echo "Deploying Elastiflow..."
  cd "$INSTALL_DIR"
  docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d
}

# Function to check and disable swap if any swap file is in use
disable_swap_if_swapfile_in_use() {
  
printf "\n\n\n*********Disabling swap file is present...\n\n"

    # Check if swap is on
    swap_status=$(swapon --show)

    if [ -n "$swap_status" ]; then
        echo "Swap is currently on."

        # Get the swap file name if it's in use (filtering for file type swaps)
        swapfile=$(swapon --show | awk '$2 == "file" {print $1}')

        if [ -n "$swapfile" ]; then
            echo "$swapfile is in use."

            # Turn off swap
            echo "Turning off swap..."
            sudo swapoff -a

            # Check if swapoff was successful
            if [ $? -eq 0 ]; then
                echo "Swap has been turned off."

                # Delete the detected swap file
                echo "Deleting $swapfile..."
                sudo rm -f "$swapfile"

                if [ $? -eq 0 ]; then
                    echo "$swapfile has been deleted."
                else
                    echo "Failed to delete $swapfile."
                fi
            else
                echo "Failed to turn off swap."
            fi
        else
            echo "No swap file found in use."
        fi
    else
        echo "Swap is currently off."
    fi
}



# Main script execution
check_root
ask_deploy
tune_system
disable_swap_if_swapfile_in_use
download_files
edit_env_file  # Open the .env file for editing
check_docker
deploy_elastiflow

echo "ElastiFlow has been deployed successfully!"
