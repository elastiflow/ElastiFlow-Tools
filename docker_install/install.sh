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
  curl -L -o "$INSTALL_DIR/readme.txt" --create-dirs "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/readme.txt"
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

# Function to deploy Elastiflow using Docker Compose
deploy_elastiflow() {
  echo "Deploying Elastiflow..."
  cd "$INSTALL_DIR"
  docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d
}

# Main script execution
check_root
ask_deploy
download_files
edit_env_file  # Open the .env file for editing
check_docker
deploy_elastiflow

echo "Elastiflow has been deployed successfully!"
