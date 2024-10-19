#!/bin/bash

# Function to check if the user is root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
  fi
}

# Function to ask the user if they want to deploy ElastiFlow
ask_deploy() {
  while true; do
    read -p "Do you want to deploy ElastiFlow? (y/n): " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) 
        break
        ;;
      [nN]|[nN][oO])
        echo "Exiting without deploying ElastiFlow."
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
  curl -L -o "$INSTALL_DIR/elastiflow_flow_compose.yml" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_flow_compose.yml"
  curl -L -o "$INSTALL_DIR/install_docker.sh" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install_docker.sh"
}

# Function to check if Docker is installed and install if necessary
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. This is required."
    while true; do
      read -p "Do you want to install Docker? (y/n): " choice
      case "$choice" in
        [yY] | [yY][eE][sS] )
          echo "Installing Docker..."
          chmod +x "$INSTALL_DIR/install_docker.sh"
          bash "$INSTALL_DIR/install_docker.sh"

          # Verify if Docker is installed after running the install script
          if ! command -v docker &> /dev/null; then
            echo "Docker installation failed. Please check the installation process and try again."
            exit 1
          else
            echo "Docker installed successfully."
          fi
          break
          ;;
        [nN] | [nN][oO] )
          echo "Docker installation declined. Exiting..."
          exit 0
          ;;
        * )
          echo "Invalid input. Please enter 'y' for yes or 'n' for no."
          ;;
      esac
    done
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


# Function to deploy ElastiFlow using Docker Compose
deploy_elastiflow() {
  echo "Deploying ElastiFlow..."
  cd "$INSTALL_DIR"
  docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_flow_compose.yml up -d
}

# Function to check and disable swap if any swap file is in use
disable_swap_if_swapfile_in_use() {
  
printf "\n\n\n*********Disabling swap file if present...\n\n"

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


# Function to download and extract ElastiFlow .deb
extract_elastiflow() {
    # Set variables
    DEB_URL="https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb"
    DEB_FILE="flow-collector_7.2.2_linux_amd64.deb"
    TEMP_DIR="/tmp/elastiflow_deb"
    TARGET_DIR="/etc/elastiflow"

    # Download the .deb file
    echo "Downloading $DEB_URL..."
    wget -O "$DEB_FILE" "$DEB_URL"

    # Check if the temporary directory exists; if not, create it
    if [ ! -d "$TEMP_DIR" ]; then
        echo "Creating directory $TEMP_DIR..."
        mkdir -p "$TEMP_DIR"
    else
        echo "$TEMP_DIR already exists, skipping creation."
    fi

    # Extract the .deb file contents
    echo "Extracting $DEB_FILE..."
    dpkg-deb -x "$DEB_FILE" "$TEMP_DIR"

    # Copy /data/etc/elastiflow contents to /etc/elastiflow
    echo "Copying extracted files to $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"
    cp -r "$TEMP_DIR/etc/elastiflow/." "$TARGET_DIR/"

    # Cleanup
    echo "Cleaning up..."
    rm -rf "$TEMP_DIR" "$DEB_FILE"

    echo "ElastiFlow yml files have been extracted!"
}


# create xpack.encryptedSavedObjects.encryptionKey and append to .env
generate_saved_objects_enc_key() {
  XPACK_SAVED_OBJECTS_KEY=$(openssl rand -base64 32)
  echo "XPACK_SAVED_OBJECTS_KEY=${XPACK_SAVED_OBJECTS_KEY}" | sudo tee -a $INSTALL_DIR/.env > /dev/null
}


# Function to check if openssl is installed and install if missing on Ubuntu/Debian
install_openssl_if_missing() {
  # Check if openssl is installed
  if ! command -v openssl &> /dev/null; then
    echo "OpenSSL is not installed. Installing OpenSSL..."

    # For Ubuntu/Debian-based systems
    if [ -f /etc/debian_version ]; then
      sudo apt update
      sudo apt install -y openssl
    else
      echo "This script is intended for Ubuntu/Debian systems only."
      exit 1
    fi
  else
    echo "OpenSSL is already installed."
  fi
}



# Main script execution
check_root
ask_deploy
tune_system
disable_swap_if_swapfile_in_use
download_files
install_openssl_if_missing
generate_saved_objects_enc_key
check_docker
extract_elastiflow
deploy_elastiflow
echo "ElastiFlow has been deployed successfully!"
