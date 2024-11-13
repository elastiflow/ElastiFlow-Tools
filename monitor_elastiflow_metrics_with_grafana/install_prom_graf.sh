#!/bin/bash

# Function to initialize by creating directories and copying files
initialize() {
  echo "Initializing setup by creating directories and copying configuration files..."

  # Create necessary directories
  sudo mkdir -p /etc/grafana/provisioning/datasources
  sudo mkdir -p /etc/prometheus

  # Check if directories were created successfully
  if [ -d "/etc/grafana/provisioning/datasources" ] && [ -d "/etc/prometheus" ]; then
    echo "Directories created successfully."

    # Copy the configuration files to their respective directories
    sudo cp prometheus.yml /etc/prometheus/prometheus.yml
    sudo cp datasource.yml /etc/grafana/provisioning/datasources/datasource.yml

    echo "Configuration files copied successfully."
  else
    echo "Failed to create directories. Exiting initialization."
    exit 1
  fi
}



check_and_install_docker() {
  # Check if Docker is installed
  if command -v docker > /dev/null 2>&1; then
    echo "Docker is already installed."
  else
    echo "Docker not found. Installing Docker..."

    # Update the package list and install dependencies
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    # Set up the directory for Docker’s GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update the package list again and install Docker
    sudo apt-get update -qq > /dev/null
    sudo apt-get install -qq -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null

    # Verify that Docker was successfully installed
    if docker --version > /dev/null 2>&1; then
      echo "Docker installation was successful."
    else
      echo "Docker installation failed."
      exit 1
    fi
  fi
}


# Function to check service health
check_health() {
  url=$1
  name=$2
  for i in {1..10}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$response" -eq 200 ]; then
      echo "$name is up and running."
      return 0
    else
      echo "Waiting for $name to be up..."
      echo $response
      sleep 5
    fi
  done
  echo "$name did not respond successfully within the time limit."
  return 1
}

# Run health checks and import the dashboard if all services are healthy
run_health_checks_and_import() {
  if check_health "http://localhost:8080/metrics" "ElastiFlow metrics" && \
     check_health "http://localhost:3000/login" "Grafana" && \
     check_health "http://localhost:9090/-/ready" "Prometheus"; then
    echo "All services are healthy. Proceeding with Grafana dashboard import."
    import_dashboard
  else
    echo "One or more services are not healthy. Dashboard import aborted."
    exit 1
  fi
}

# Function to download and import the Grafana dashboard
import_dashboard() {
  echo "Downloading the ElastiFlow dashboard JSON..."
  curl -o elastiflow_dashboard.json https://grafana.com/api/dashboards/17306/revisions/3/download

  # Check if the download was successful
  if [ $? -eq 0 ]; then
    echo "Download successful. Replacing data source placeholder..."

    # Replace ${DS_PROMETHEUS} with prometheus_uid123 in the downloaded JSON
    replace_datasource_placeholder "elastiflow_dashboard.json"

    # Import the modified dashboard into Grafana
    curl -X POST -H "Content-Type: application/json" -u "admin:admin" \
      -d "{\"dashboard\": $(cat elastiflow_dashboard.json), \"overwrite\": true}" \
      http://localhost:3000/api/dashboards/db

    # Check if the import was successful
    if [ $? -eq 0 ]; then
      echo "Dashboard imported successfully."
    else
      echo "Dashboard import failed."
      exit 1
    fi
  else
    echo "Failed to download the dashboard JSON."
    exit 1
  fi
}

replace_datasource_placeholder() {
  local file_path=$1
  sed -i 's/\${DS_PROMETHEUS}/prometheus_uid123/g' "$file_path"
}



# Function to install Prometheus and Grafana using Docker Compose
install_prom_graf() {
  echo "Starting Prometheus and Grafana using Docker Compose..."
  docker compose -f docker_compose_prom_graf.yml up -d

  # Confirmation message for Docker Compose
  if [ $? -eq 0 ]; then
    echo "Docker Compose started using docker_compose_prom_graf.yml"
  else
    echo "Failed to start Docker Compose."
    exit 1
  fi
}

check_root() {
  # Check if the script is run as root
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
  fi
}



# Main function to initialize, install Prometheus and Grafana, and run health checks with dashboard import
main() {
  check_root
  check_and_install_docker
  initialize
  install_prom_graf
  run_health_checks_and_import
}

# Execute main function
main
