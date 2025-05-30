#!/bin/bash

# ElastiFlow PoC Configurator for configuring ElastiFlow Virtual Appliance
# Version: 2.8.4.3.2
# Author: O.J. Wolanyk

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

flow_collector_version="7.6.0"
flow_kibana_dashboards_version="8.14.x"
flow_kibana_dashboards_codex_ecs="codex"
osd_flow_dashboards_version="2.14.x"
flow_config_path="/etc/elastiflow/flowcoll.yml"

snmp_collector_version="7.6.0"
snmp_kibana_dashboards_version="8.14.x"
snmp_kibana_dashboards_codex_ecs="codex"
osd_snmp_dashboards_version="2.14.x"
snmp_config_path="/etc/elastiflow/snmpcoll.yml"



elastic_username="elastic"
ip_address=""
dashboard_url=""

SEARCH_ENGINE='Elastic'


check_service() {
    local service_name=$1
    systemctl is-active --quiet "$service_name"
    if [[ $? -eq 0 ]]; then
        echo "$service_name is running."
        return 0
    else
        return 1
    fi
}

which_search_engine(){
  # Check for Elasticsearch
  check_service "elasticsearch"
  es_running=$?

  # Check for OpenSearch
  check_service "opensearch"
  os_running=$?

  if [[ $es_running -eq 0 ]]; then
      SEARCH_ENGINE='Elastic'
  elif [[ $os_running -eq 0 ]]; then
      SEARCH_ENGINE='Opensearch'
  fi
  
}

display_system_info() {
  # Main partition size in GB
  main_partition_size=$(df -h / | awk 'NR==2 {print $2}')
  echo "Main partition size: $main_partition_size"

  # Used partition space in GB
  used_partition_space=$(df -h / | awk 'NR==2 {print $3}')
  echo "Used partition space: $used_partition_space"

  # Free partition space in percentage and GB
  free_partition_space_percent=$(df -h / | awk 'NR==2 {print $5}')
  free_partition_space_gb=$(df -h / | awk 'NR==2 {print $4}')
  echo "Free partition space: $free_partition_space_gb ($free_partition_space_percent)"

  # Installed RAM in GB
  installed_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
  echo "Installed RAM: ${installed_ram_gb}GB"

  # Number of physical CPUs
  physical_cpus=$(lscpu | awk '/^Socket\(s\):/{print $2}')
  echo "Number of physical CPUs: $physical_cpus"

  # Number of physical cores per CPU
  cores_per_cpu=$(lscpu | awk '/^Core\(s\) per socket:/{print $4}')
  echo "Number of physical cores per CPU: $cores_per_cpu"

  # Total number of cores
  total_cores=$((physical_cpus * cores_per_cpu))
  echo "Total number of cores: $total_cores"
}


display_version() {
  local file="$1"
  local version=$(grep -m 1 '^# Version: ' "$file" | awk '{print $3}')
  if [[ -z "$version" ]]; then
    echo "Failed to detect the version in $file"
  else
    echo "Version of $(basename "$file") script: $version"
  fi
}


install_snmp_collector() {

  # Prompt the user for the ElastiFlow Account ID
  while true; do
    read -p "Enter your ElastiFlow Account ID (or 'q' to quit): " elastiflow_account_id
    if [[ $elastiflow_account_id == "q" ]]; then
      return
    elif [[ -z $elastiflow_account_id ]]; then
      print_message "ElastiFlow Account ID cannot be empty. Please enter a valid ID." "$RED"
    else
      break
    fi
  done

  # Prompt the user for the SNMP flow key
  while true; do
    read -p "Enter your ElastiFlow License Key (or 'q' to quit): " ef_license_key
    if [[ $ef_license_key == "q" ]]; then
      return
    elif [[ -z $ef_license_key ]]; then
      print_message "ElastiFlow License Key cannot be empty. Please enter a valid key." "$RED"
    else
      break
    fi
  done


  # Extract the Elasticsearch password from the configuration file
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$flow_config_path" | awk -F"'" '{print $2}')


  if [ -z "$elastic_password" ]; then
    print_message "Failed to extract Elasticsearch password from $flow_config_path" "$RED"
    return
  fi

  snmp_config_strings=(
    "EF_LICENSE_ACCEPTED" "EF_LICENSE_ACCEPTED: 'true'"
    "EF_ACCOUNT_ID" "EF_ACCOUNT_ID: \"${elastiflow_account_id}\""
    "EF_LICENSE_TELEMETRY_HOSTS" "EF_LICENSE_TELEMETRY_HOSTS: 0"
    "EF_LICENSE_KEY" "EF_LICENSE_KEY: '${ef_license_key}'"
    "EF_OUTPUT_ELASTICSEARCH_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ENABLE: 'true'"
    "EF_OUTPUT_ELASTICSEARCH_ADDRESSES" "EF_OUTPUT_ELASTICSEARCH_ADDRESSES: '127.0.0.1:9200'"
    "EF_OUTPUT_ELASTICSEARCH_PASSWORD" "EF_OUTPUT_ELASTICSEARCH_PASSWORD: '$elastic_password'"
    "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE: 'true'"
    "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION" "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION: 'true'"
    "EF_LOGGER_FILE_LOG_ENABLE" "EF_LOGGER_FILE_LOG_ENABLE:  'true'"
    "EF_LOGGER_FILE_LOG_FILENAME" "EF_LOGGER_FILE_LOG_FILENAME: '/var/log/elastiflow/snmpcoll/snmpcoll.log'"
    "EF_INPUT_SNMP_PERSIST_ENABLE" "EF_INPUT_SNMP_PERSIST_ENABLE: 'false'"
  )


  print_message "Installing ElastiFlow Unified SNMP Collector $snmp_collector_version..." "$GREEN"
  
  # Update package list and install prerequisites
  apt-get update -qq
  apt-get install -qq -y snmp snmpd snmp-mibs-downloader curl apt-transport-https gnupg
  
  # Download the ElastiFlow SNMP collector package
  wget -q -O elastiflow-snmpcollector.deb "https://elastiflow-releases.s3.us-east-2.amazonaws.com/snmp-collector/snmp-collector_${snmp_collector_version}_linux_amd64.deb"

  # Install the package
  dpkg -i elastiflow-snmpcollector.deb

  find_and_replace "$snmp_config_path" "${snmp_config_strings[@]}"

  # Enable and start the SNMP collector service
  systemctl enable snmpcoll.service
  systemctl start snmpcoll.service

  # Install SNMP dashboards
  printf "\n\n\n*********Downloading and installing ElastiFlow SNMP dashboards $kibana_dashboards_codex_ecs $snmp_kibana_dashboards_version\n\n"

  # Remove the existing directory if it exists
  if [ -d "/etc/elastiflow_for_elasticsearch" ]; then
    rm -rf /etc/elastiflow_for_elasticsearch
  fi
  
  # Clone the repository
  git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/

  # Path to the downloaded JSON file
  json_file="/etc/elastiflow_for_elasticsearch/kibana/snmp/kibana-$snmp_kibana_dashboards_version-snmp-$snmp_kibana_dashboards_codex_ecs.ndjson"
  
  # Perform find and replace in the JSON file
  sed -i 's/elastiflow-\*-codex-\*/elastiflow-telemetry_\*-codex-\*/g' "$json_file"

  response=$(curl --silent --show-error --fail --connect-timeout 10 -X POST -u "$elastic_username:$elastic_password" \
    "localhost:5601/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" \
    --form file=@"$json_file" \
    -H 'kbn-xsrf: true')

  dashboards_success=$(echo "$response" | jq -r '.success')

  if [ "$dashboards_success" == "true" ]; then
    print_message "SNMP dashboards installed successfully." "$GREEN"
  else
    print_message "SNMP dashboards not installed successfully." "$RED"
    echo "Debug: API response:"
    echo "$response"
  fi

  # Check the status of the service
  if systemctl is-active --quiet snmpcoll.service; then
    print_message "ElastiFlow Unified SNMP Collector installed and running." "$GREEN"
  else
    print_message "Failed to start ElastiFlow Unified SNMP Collector." "$RED"
  fi
}


reset_elastic_password() {
  local elasticsearch_service_name="elasticsearch"  # Change this if your Elasticsearch service name is different

#  echo "Stopping Elasticsearch service..."
#  sudo systemctl stop "$elasticsearch_service_name"

#  if [[ $? -ne 0 ]]; then
#    echo "Failed to stop Elasticsearch service."
#    return
#  fi

  echo "Resetting the elastic user password..."
  sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password --username elastic -i -f --url https://localhost:9200

  if [[ $? -ne 0 ]]; then
    echo "Failed to reset the password for user 'elastic'."
    return
  fi

#  echo "Starting Elasticsearch service..."
#  sudo systemctl start "$elasticsearch_service_name"

#  if [[ $? -ne 0 ]]; then
#    echo "Failed to start Elasticsearch service."
#    return
#  fi

  # Update password in Elastiflow (if needed)
  read -sp "Enter new password for 'elastic' user to update Elastiflow configuration: " new_elastic_password
  echo

  # Update password in Elastiflow
  elastiflow_config_strings=("EF_OUTPUT_ELASTICSEARCH_PASSWORD" "EF_OUTPUT_ELASTICSEARCH_PASSWORD: '$new_elastic_password'")
  find_and_replace "$flow_config_path" "${elastiflow_config_strings[@]}"

  # Restart all services
  reload_and_restart_services "flowcoll.service"

  echo "Password for user 'elastic' has been reset successfully."
}

reset_opensearch_password(){
  while true; do
    echo "Password must be strong. Min 12 characters with at least 1 number, lowercase, uppercase and special character"
    read -sp "Enter new password for Opensearch user 'admin': " new_admin_password
    echo
    check_password $new_admin_password
    if [[ $? -eq 0 ]]; then
      break

    fi
  done

  password_hash=$(bash /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh -p $new_admin_password | grep -o '\$.*')
  echo $password_hash
  escaped_hash=$( echo "$password_hash" | sed -e 's/\\/\\\\/g' -e 's/\$/\\$/g' -e 's/"/\\"/g' -e 's/`/\\`/g' -e 's/\//\\\//g')
  echo $escaped_hash
  sed -i "/^admin:/,/^[^ ]/s/^\(\s*hash:\).*/\1 \"$escaped_hash\"/" "/etc/opensearch/opensearch-security/internal_users.yml"

  bash /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh -f /etc/opensearch/opensearch-security/internal_users.yml -cacert  /etc/opensearch/root-ca.pem   -cert /etc/opensearch/kirk.pem   -key /etc/opensearch/kirk-key.pem

  # Update password for Opensearch Dashboards
  ord_config_strings=("opensearch.password:" "opensearch.password: '$new_admin_password'")
  find_and_replace "/etc/opensearch-dashboards/opensearch_dashboards.yml" "${ord_config_strings[@]}"
  

  # Update password in Elastiflow
  elastiflow_config_strings=("EF_OUTPUT_OPENSEARCH_PASSWORD" "EF_OUTPUT_OPENSEARCH_PASSWORD: '$new_admin_password'")

  find_and_replace "$flow_config_path" "${elastiflow_config_strings[@]}"

  # Restart all services
  reload_and_restart_services "flowcoll.service" "opensearch-dashboards.service"

}

check_password() {
    local password="$1"

    # Check if password is at least 12 characters long
    if [[ ${#password} -lt 12 ]]; then
        echo "Password must be at least 12 characters long."
        return 1
    fi

    # Check for at least one uppercase letter
    if ! [[ "$password" =~ [A-Z] ]]; then
        echo "Password must contain at least one uppercase letter."
        return 1
    fi

    # Check for at least one lowercase letter
    if ! [[ "$password" =~ [a-z] ]]; then
        echo "Password must contain at least one lowercase letter."
        return 1
    fi

    # Check for at least one number
    if ! [[ "$password" =~ [0-9] ]]; then
        echo "Password must contain at least one number."
        return 1
    fi

    # Check for at least one special character
    if ! [[ "$password" =~ [\@\#\$\%\^\&\*\_\+\!\~\=\<\>] ]]; then
        echo "Password must contain at least one special character."
        return 1
    fi

    # If all checks pass
    echo "Password is strong."
    return 0
}

verify_ef_flow_configured_pw_for_elastic(){
  # Extract the Elasticsearch password from the configuration file
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$flow_config_path" | awk -F"'" '{print $2}')

  # Check if the password was successfully extracted
  if [ -z "$elastic_password" ]; then
    print_message "Failed to extract Elasticsearch password from $flow_config_path" '\033[0;31m'
    exit 1
  fi

  # Verify the password via Kibana
  kibana_url="http://localhost:5601"
  response=$(curl -s -o /dev/null -w "%{http_code}" -u "elastic:$elastic_password" "$kibana_url/api/status")

  # Check the response code
  if [ "$response" -eq 200 ]; then
    print_message "Elastic password in flowcoll.yml is correct. Authentication successful! - \"$elastic_password\"" "$GREEN"
  else
    print_message "Elastic password in flowcoll.yml not correct. Authentication failed with response code: $response" "$RED"
  fi
}

verify_ef_snmp_configured_pw_for_elastic(){
  # Extract the Elasticsearch password from the configuration file
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$snmp_config_path" | awk -F"'" '{print $2}')

  # Check if the password was successfully extracted
  if [ -z "$elastic_password" ]; then
    print_message "Failed to extract Elasticsearch password from $snmp_config_path" '\033[0;31m'
    exit 1
  fi

  # Verify the password via Kibana
  kibana_url="http://localhost:5601"
  response=$(curl -s -o /dev/null -w "%{http_code}" -u "elastic:$elastic_password" "$kibana_url/api/status")

  # Check the response code
  if [ "$response" -eq 200 ]; then
    print_message "Elastic password in snmpcoll.yml is correct. Authentication successful! - \"$elastic_password\"" "$GREEN"
  else
    print_message "Elastic password in snmpcoll.yml not correct. Authentication failed with response code: $response" "$RED"
  fi
}


display_system_info() {
  # Main partition size in GB
  main_partition_size=$(df -h / | awk 'NR==2 {print $2}')
  echo "Main partition size: $main_partition_size"

  # Used partition space in GB
  used_partition_space=$(df -h / | awk 'NR==2 {print $3}')
  echo "Used partition space: $used_partition_space"

  # Free partition space in percentage and GB
  free_partition_space_percent=$(df -h / | awk 'NR==2 {print $5}')
  free_partition_space_gb=$(df -h / | awk 'NR==2 {print $4}')
  echo "Free partition space: $free_partition_space_gb ($free_partition_space_percent)"

  # Installed RAM in GB
  installed_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
  echo "Installed RAM: ${installed_ram_gb}GB"

  # Number of physical CPUs
  physical_cpus=$(lscpu | awk '/^Socket\(s\):/{print $2}')
  echo "Number of physical CPUs: $physical_cpus"

  # Number of physical cores per CPU
  cores_per_cpu=$(lscpu | awk '/^Core\(s\) per socket:/{print $4}')
  echo "Number of physical cores per CPU: $cores_per_cpu"

  # Total number of cores
  total_cores=$((physical_cpus * cores_per_cpu))
  echo "Total number of cores: $total_cores"
}

# Function to install ElastiFlow Flow Collector from a dynamically scraped URL with verification
update_flow_collector() {
    local DOC_URL="https://docs.elastiflow.com/docs/flowcoll/install_linux"

    echo "Scraping $DOC_URL for download details..."

    # Function to validate a URL
    validate_url() {
        if curl --output /dev/null --silent --head --fail "$1"; then
            echo "$1"
        else
            echo ""
        fi
    }

    # Scrape and validate the first valid URL for the .deb file
    local DEB_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb' | head -n 1)
    DEB_URL=$(validate_url "$DEB_URL")

    # Scrape and validate the first valid URL for the .sha256 checksum file
    local SHA256_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sha256' | head -n 1)
    SHA256_URL=$(validate_url "$SHA256_URL")

    # Scrape and validate the first valid URL for the GPG signature file (.deb.sig)
    local GPG_SIG_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+flow-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sig' | head -n 1)
    GPG_SIG_URL=$(validate_url "$GPG_SIG_URL")

    # Scrape for the GPG key ID
    local GPG_KEY_ID=$(curl -sL $DOC_URL | grep -oP 'class="token plain">echo &quot;\K[A-F0-9]{40}' | head -n 1)

    # Scrape and validate the URL for the public key (.pgp)
    local GPG_PUBKEY_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+elastiflow\.pgp' | head -n 1)
    GPG_PUBKEY_URL=$(validate_url "$GPG_PUBKEY_URL")

    # Check if the DEB_URL was found and is valid
    if [ -z "$DEB_URL" ]; then
        echo "Error: Could not find a valid .deb file URL in $DOC_URL."
        exit 1
    fi

    echo "Found DEB URL: $DEB_URL"
    echo "Found SHA256 URL: $SHA256_URL"
    echo "Found GPG Signature URL: $GPG_SIG_URL"
    echo "Found GPG Key ID: $GPG_KEY_ID"
    echo "Found GPG public key URL: $GPG_PUBKEY_URL"


    # Extract the filename from the URL
    local FILENAME=$(basename "$DEB_URL")

    # Extract the version number from the filename
    local REMOTE_VERSION=$(echo "$FILENAME" | grep -oP 'flow-collector_\K[0-9]+\.[0-9]+\.[0-9]+')

    # Check the currently installed version of ElastiFlow
    local CURRENT_VERSION=$(/usr/share/elastiflow/bin/flowcoll -version 2>/dev/null || echo "None")

    echo "Current installed version: ${CURRENT_VERSION}"
    echo "Remote version: $REMOTE_VERSION"

    # Prompt the user to confirm if they want to install the remote version
    read -p "Do you want to install the remote version $REMOTE_VERSION? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Installation aborted by user."
        exit 0
    fi

    # Download all files to /tmp
    local DOWNLOAD_DIR="/tmp"
    # Extract the filename from the URL and combine it with the download directory path
    local DEB_FILE="$DOWNLOAD_DIR/$FILENAME"
    echo "DEB file will be downloaded to: $DEB_FILE"

    # Download the .deb file
    wget -O "$DEB_FILE" "$DEB_URL" || {
        echo "Error: Failed to download .deb file."
        exit 1
    }

    # Attempt to download the checksum file
    if [ -n "$SHA256_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$SHA256_URL" || {
            echo "Warning: Failed to download checksum file."
            read -p "Do you want to continue without checksum verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            SHA256_URL=""
        }
    fi

    # Attempt to download the GPG signature file
    if [ -n "$GPG_SIG_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" "$GPG_SIG_URL" || {
            echo "Warning: Failed to download GPG signature file."
            read -p "Do you want to continue without GPG signature verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            GPG_SIG_URL=""
        }
    fi


# Attempt to download the GPG public key file
if [ -n "$GPG_PUBKEY_URL" ]; then
    GPG_PUBKEY_FILE="$DOWNLOAD_DIR/$(basename $GPG_PUBKEY_URL)"
    wget -O "$GPG_PUBKEY_FILE" "$GPG_PUBKEY_URL" || {
        echo "Warning: Failed to download GPG public key file."
        read -p "Do you want to continue without the GPG public key? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Installation aborted by user."
            exit 1
        fi
        GPG_PUBKEY_URL=""
    }
fi

# Import GPG public key
if [ -n "$GPG_PUBKEY_FILE" ] && [ -f "$GPG_PUBKEY_FILE" ]; then
    echo "Importing GPG public key..."
    gpg --import "$GPG_PUBKEY_FILE" || {
        echo "Warning: Failed to import GPG public key."
        read -p "Do you want to continue without importing the GPG public key? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Installation aborted by user."
            exit 1
        fi
    }
else
    echo "No GPG public key file found. Skipping GPG key import."
fi

    # Import and trust the GPG key
    if [ -n "$GPG_KEY_ID" ]; then
        echo "Importing and trusting the GPG key..."
        echo "$GPG_KEY_ID:6:" | gpg --import-ownertrust || {
            echo "Warning: Failed to import GPG key."
            read -p "Do you want to continue without GPG key import? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
        }

    else
        echo "No GPG key ID found. Skipping GPG key import."
    fi

    # Verify the checksum if the checksum file was downloaded
    if [ -n "$SHA256_URL" ]; then
        echo "Verifying checksum..."
        local ACTUAL_CHECKSUM=$(sha256sum $DEB_FILE | awk '{print $1}')
        local EXPECTED_CHECKSUM=$(cat "$DOWNLOAD_DIR/$(basename $SHA256_URL)" | awk '{print $1}')
        if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            echo "Error: Checksum verification failed."
            rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)"
            exit 1
        else
            echo "Checksum verification passed."
        fi
    else
        echo "Skipping checksum verification."
    fi

    # Verify the GPG signature if the signature file was downloaded
    if [ -n "$GPG_SIG_URL" ]; then
        echo "Verifying GPG signature..."
        gpg --verify "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" $DEB_FILE || {
            echo "Warning: GPG verification failed. Continuing without GPG verification."
        }
        echo "GPG verification passed."
    else
        echo "No GPG signature file found. Skipping GPG verification."
    fi

    # Install the .deb package using apt
    echo "Installing the downloaded .deb file using apt..."
    sudo apt install -y $DEB_FILE || {
        echo "Error: Failed to install the package."
        exit 1
    }

    # Clean up the downloaded files
    echo "Cleaning up..."
    rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)"

    echo "Installation completed successfully."
}


# Function to install ElastiFlow Flow Collector from a dynamically scraped URL with verification
update_snmp_collector() {
    local DOC_URL="https://docs.elastiflow.com/docs/snmpcoll/install_linux"

    echo "Scraping $DOC_URL for download details..."

    # Function to validate a URL
    validate_url() {
        if curl --output /dev/null --silent --head --fail "$1"; then
            echo "$1"
        else
            echo ""
        fi
    }

    # Scrape and validate the first valid URL for the .deb file
    local DEB_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+snmp-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb' | head -n 1)
    DEB_URL=$(validate_url "$DEB_URL")

    # Scrape and validate the first valid URL for the .sha256 checksum file
    local SHA256_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+snmp-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sha256' | head -n 1)
    SHA256_URL=$(validate_url "$SHA256_URL")

    # Scrape and validate the first valid URL for the GPG signature file (.deb.sig)
    local GPG_SIG_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+snmp-collector_[0-9]+\.[0-9]+\.[0-9]+_linux_amd64\.deb\.sig' | head -n 1)
    GPG_SIG_URL=$(validate_url "$GPG_SIG_URL")

    # Scrape for the GPG key ID
    local GPG_KEY_ID=$(curl -sL $DOC_URL | grep -oP 'class="token plain">echo &quot;\K[A-F0-9]{40}' | head -n 1)

    # Scrape and validate the URL for the public key (.pgp)
    local GPG_PUBKEY_URL=$(curl -sL $DOC_URL | grep -oP 'https://[^\"]+elastiflow\.pgp' | head -n 1)
    GPG_PUBKEY_URL=$(validate_url "$GPG_PUBKEY_URL")

    # Check if the DEB_URL was found and is valid
    if [ -z "$DEB_URL" ]; then
        echo "Error: Could not find a valid .deb file URL in $DOC_URL."
        exit 1
    fi

    echo "Found DEB URL: $DEB_URL"
    echo "Found SHA256 URL: $SHA256_URL"
    echo "Found GPG Signature URL: $GPG_SIG_URL"
    echo "Found GPG Key ID: $GPG_KEY_ID"
    echo "Found GPG public key URL: $GPG_PUBKEY_URL"


    # Extract the filename from the URL
    local FILENAME=$(basename "$DEB_URL")

    # Extract the version number from the filename
    local REMOTE_VERSION=$(echo "$FILENAME" | grep -oP 'snmp-collector_\K[0-9]+\.[0-9]+\.[0-9]+')

    # Check the currently installed version of ElastiFlow SNMP Collector
    local CURRENT_VERSION=$(/usr/share/elastiflow/bin/snmpcoll -version 2>/dev/null || echo "None")

    echo "Current installed version: ${CURRENT_VERSION}"
    echo "Remote version: $REMOTE_VERSION"

    # Prompt the user to confirm if they want to install the remote version
    read -p "Do you want to install the remote version $REMOTE_VERSION? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Installation aborted by user."
        exit 0
    fi

    # Download all files to /tmp
    local DOWNLOAD_DIR="/tmp"
    # Extract the filename from the URL and combine it with the download directory path
    local DEB_FILE="$DOWNLOAD_DIR/$FILENAME"
    echo "DEB file will be downloaded to: $DEB_FILE"

    # Download the .deb file
    wget -O "$DEB_FILE" "$DEB_URL" || {
        echo "Error: Failed to download .deb file."
        exit 1
    }

    # Attempt to download the checksum file
    if [ -n "$SHA256_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$SHA256_URL" || {
            echo "Warning: Failed to download checksum file."
            read -p "Do you want to continue without checksum verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            SHA256_URL=""
        }
    fi

    # Attempt to download the GPG signature file
    if [ -n "$GPG_SIG_URL" ]; then
        wget -O "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" "$GPG_SIG_URL" || {
            echo "Warning: Failed to download GPG signature file."
            read -p "Do you want to continue without GPG signature verification? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
            GPG_SIG_URL=""
        }
    fi


  # Attempt to download the GPG public key file
  if [ -n "$GPG_PUBKEY_URL" ]; then
      GPG_PUBKEY_FILE="$DOWNLOAD_DIR/$(basename $GPG_PUBKEY_URL)"
      wget -O "$GPG_PUBKEY_FILE" "$GPG_PUBKEY_URL" || {
          echo "Warning: Failed to download GPG public key file."
          read -p "Do you want to continue without the GPG public key? [y/N]: " CONFIRM
          if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
              echo "Installation aborted by user."
              exit 1
          fi
          GPG_PUBKEY_URL=""
      }
  fi

  # Import GPG public key
  if [ -n "$GPG_PUBKEY_FILE" ] && [ -f "$GPG_PUBKEY_FILE" ]; then
      echo "Importing GPG public key..."
      gpg --import "$GPG_PUBKEY_FILE" || {
          echo "Warning: Failed to import GPG public key."
          read -p "Do you want to continue without importing the GPG public key? [y/N]: " CONFIRM
          if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
              echo "Installation aborted by user."
              exit 1
          fi
      }
  else
      echo "No GPG public key file found. Skipping GPG key import."
  fi

    # Import and trust the GPG key
    if [ -n "$GPG_KEY_ID" ]; then
        echo "Importing and trusting the GPG key..."
        echo "$GPG_KEY_ID:6:" | gpg --import-ownertrust || {
            echo "Warning: Failed to import GPG key."
            read -p "Do you want to continue without GPG key import? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Installation aborted by user."
                exit 1
            fi
        }

    else
        echo "No GPG key ID found. Skipping GPG key import."
    fi

    # Verify the checksum if the checksum file was downloaded
    if [ -n "$SHA256_URL" ]; then
        echo "Verifying checksum..."
        local ACTUAL_CHECKSUM=$(sha256sum $DEB_FILE | awk '{print $1}')
        local EXPECTED_CHECKSUM=$(cat "$DOWNLOAD_DIR/$(basename $SHA256_URL)" | awk '{print $1}')
        if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            echo "Error: Checksum verification failed."
            rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)"
            exit 1
        else
            echo "Checksum verification passed."
        fi
    else
        echo "Skipping checksum verification."
    fi

    # Verify the GPG signature if the signature file was downloaded
    if [ -n "$GPG_SIG_URL" ]; then
        echo "Verifying GPG signature..."
        gpg --verify "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)" $DEB_FILE || {
            echo "Warning: GPG verification failed. Continuing without GPG verification."
        }
        echo "GPG verification passed."
    else
        echo "No GPG signature file found. Skipping GPG verification."
    fi

    # Install the .deb package using apt
    echo "Installing the downloaded .deb file using apt..."
    sudo apt install -y $DEB_FILE || {
        echo "Error: Failed to install the package."
        exit 1
    }

    # Clean up the downloaded files
    echo "Cleaning up..."
    rm -f $DEB_FILE "$DOWNLOAD_DIR/$(basename $SHA256_URL)" "$DOWNLOAD_DIR/$(basename $GPG_SIG_URL)"

    echo "Installation completed successfully."
}



change_elasticsearch_password() {
  while true; do
    # Prompt for current password
    read -s -p "Enter current Elasticsearch password: " old_elastic_password
    echo
    
    # Validate current password is not empty
    if [ -z "$old_elastic_password" ]; then
      echo "Current password cannot be empty."
      continue
    fi

    # Loop until new passwords match
    while true; do
      # Prompt for new password
      read -s -p "Enter new Elasticsearch password: " new_elastic_password
      echo
      read -s -p "Confirm new Elasticsearch password: " confirm_new_elastic_password
      echo

      # Validate new password is not empty and matches confirmation
      if [ -z "$new_elastic_password" ]; then
        echo "New password cannot be empty."
      elif [ "$new_elastic_password" != "$confirm_new_elastic_password" ]; then
        echo "Passwords do not match. Please try again."
      else
        break
      fi
    done

    # Change current Elasticsearch password
    response=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST -u "$elastic_username:$old_elastic_password" "https://localhost:9200/_security/user/elastic/_password" -H 'Content-Type: application/json' -d"
    {
      \"password\": \"$new_elastic_password\"
    }")

    if [ "$response" -eq 200 ]; then
      echo "Password successfully changed."
      break
    else
      echo "Failed to change password. HTTP response code: $response"
      read -p "Do you want to try again? (y/n): " retry_choice
      if [[ $retry_choice != "y" ]]; then
        exit 1
      fi
    fi
  done

  # Update password in Elastiflow
  elastiflow_config_strings=("EF_OUTPUT_ELASTICSEARCH_PASSWORD" "EF_OUTPUT_ELASTICSEARCH_PASSWORD: '$new_elastic_password'")

  find_and_replace "$flow_config_path" "${elastiflow_config_strings[@]}"

  # Restart all services
  reload_and_restart_services "flowcoll.service"
}



check_for_updates() {
  # Dynamically determine the path to the current script
  local current_script=$(realpath "$0")
  local new_script_url="https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/configure/configure.sh"
  local tmp_script="/tmp/configure_script_update.sh"

  echo "Checking for updates..."
  echo "Current script path: $current_script"

  wget -q -O "$tmp_script" "$new_script_url"

  if [[ $? -ne 0 ]]; then
    echo "Failed to check for updates."
    return
  fi

  echo "Downloaded new script to $tmp_script."

  local new_version=$(grep -m 1 '^# Version: ' "$tmp_script" | awk '{print $3}')
  local current_version=$(grep -m 1 '^# Version: ' "$current_script" | awk '{print $3}')

  echo "Current version: $current_version"
  echo "Remote version: $new_version"

  if [[ -z "$current_version" ]]; then
    echo "Failed to detect the current version."
    return
  fi

  if [[ "$new_version" > "$current_version" ]]; then
    echo "Remote version $new_version available."

    while true; do
      read -t 10 -p "Do you want to update to the Remote version? (y/n) [n]: " update_choice
      update_choice=${update_choice:-n}

      if [[ $update_choice == "y" || $update_choice == "n" ]]; then
        break
      else
        echo "Invalid input. Please enter 'y' or 'n'."
      fi
    done

    if [[ $update_choice == "y" ]]; then
      echo "Updating to version $new_version..."
      cp "$tmp_script" "$current_script"
      chmod +x "$current_script"
      echo "Update successful. Restarting script..."
      exec "$current_script"
    else
      echo "Update skipped."
    fi
  else
    echo "No updates available."
  fi

  echo "Cleaning up temporary script."
  rm -f "$tmp_script"
}


# Helper function to print messages with color
print_message() {
  local message=$1
  local color=$2
  echo -e "${color}${message}${NC}"
}

# Function to install Docker
install_docker() {
    echo "Docker is not installed. Installing Docker..."
    
    # Add Docker's official GPG key
    apt-get update -qq > /dev/null
    apt-get install -qq -y ca-certificates curl > /dev/null
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
}


display_info() {
  version=$(java -version 2>&1)
  echo -e "Installed Java version: $version\n"
  version=$(lsb_release -d | awk -F'\t' '{print $2}')
  echo -e "Operating System: $version\n"
  display_system_info
}


perform_health_check() {
  clear
  # Create a timestamped file
  timestamp=$(date +"%Y%m%d_%H%M%S")
  output_file="healthcheck_$timestamp.log"
  full_path=$(realpath "$output_file")

  echo "Health check output will be saved to: $full_path"

  {
    get_host_ip
    
    print_message "\n\n************* General *************" "$NC"
    display_info
    print_message "IP address: $ip_address" "$GREEN"
    netplan_file=$(find /etc/netplan -name "*.yaml" | head -n 1)
    print_message "Netplan file: $netplan_file" "$GREEN"
    printf "***\n"
    cat "$netplan_file"
    printf "***\n"
    default_gateway=$(ip route | grep default | awk '{print $3}')
    if [ -n "$default_gateway" ]; then
      if ping -c 1 $default_gateway &> /dev/null; then
        print_message "Default gateway $default_gateway reachable" "$GREEN"
      else
        print_message "Default gateway $default_gateway not reachable" "$RED"
      fi
    else
      print_message "Default gateway is not set" "$RED"
    fi

    if wget -q --spider http://google.com; then
      print_message "Internet connection is available" "$GREEN"
    else
      print_message "Internet connection is not available" "$RED"
    fi

    print_message "************* Flowcoll ************" "$NC"
    version=$(/usr/share/elastiflow/bin/flowcoll -version)
    echo -e "Installed ElastiFlow Flow version: $version"
    version=$flow_kibana_dashboards_version
    echo -e "Installed ElastiFlow Flow Dashboards version: $flow_kibana_dashboards_codex_ecs $version"
    
    verify_ef_flow_configured_pw_for_elastic
    
    get_dashboard_url "ElastiFlow (flow): Overview"
    if [ "$dashboard_url" == "Dashboard not found" ]; then
      print_message "Dashboard URL: $dashboard_url" "$RED"
    else
      print_message "Dashboard URL: $dashboard_url" "$GREEN"
    fi

    if systemctl is-active --quiet flowcoll.service; then
      print_message "flowcoll.service is running" "$GREEN"
    else
      print_message "flowcoll.service is not running" "$RED"
    fi

    if journalctl -u flowcoll.service | grep -iq "level=error"; then
    print_message "Errors found in flowcoll.service logs:" "$RED"
    #journalctl -u flowcoll.service | grep -i "level=error"
  else
    print_message "No errors found in flowcoll.service logs" "$GREEN"
  fi

    response=$(curl -s http://localhost:8080/readyz)
    if echo "$response" | grep -q "200"; then
      print_message "Readyz: $response" "$GREEN"
    else
      print_message "Readyz: $response" "$RED"
    fi

    response=$(curl -s http://localhost:8080/livez)
    if echo "$response" | grep -q "200"; then
      print_message "Livez: $response" "$GREEN"
    else
      print_message "Livez: $response" "$RED"
    fi

    for port in 2055 4739 6343 9995; do
      if netstat -tuln | grep -q ":$port"; then
        print_message "Port $port is open" "$GREEN"
      else
        print_message "Port $port is not open" "$RED"
      fi
    done

    # Path to the flowcoll.yml file
    flowcoll_file="/etc/elastiflow/flowcoll.yml"

    if [ -f "$flowcoll_file" ]; then
      # Extract values from the flowcoll.yml file
      ef_account_id=$(grep '^EF_ACCOUNT_ID: ' "$flowcoll_file" | awk '{print $2}' | tr -d '"')
      ef_license_key=$(grep '^EF_LICENSE_KEY: ' "$flowcoll_file" | awk '{print $2}' | tr -d '"')
      ef_license_accepted=$(grep '^EF_LICENSE_ACCEPTED: ' "$flowcoll_file" | awk '{print $2}' | tr -d '"')
    fi

    if [ -n "$ef_account_id" ] && [ -n "$ef_license_key" ] && [ "$ef_license_accepted" == "true" ]; then
      print_message "EF_LICENSE_ACCEPTED: $ef_license_accepted, EF_ACCOUNT_ID: $ef_account_id, EF_LICENSE_KEY: $ef_license_key" "$GREEN"
    else
      print_message "ElastiFlow account ID, license key, or license accepted is not correctly configured" "$RED"
    fi

    if grep -q '^EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: "true"' /etc/elastiflow/flowcoll.yml && grep -q '^EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: "true"' /etc/elastiflow/flowcoll.yml; then
      print_message "MaxMind enrichment is active" "$GREEN"
    else
      print_message "MaxMind enrichment is not active" "$RED"
    fi

    if grep -q '^EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE: ["'"'"']true["'"'"']' /etc/elastiflow/flowcoll.yml; then
      print_message "DNS enrichment is active" "$GREEN"
    else
      print_message "DNS enrichment is not active" "$RED"
    fi

    if grep -q '^EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_ENABLE: ["'"'"']true["'"'"']' /etc/elastiflow/flowcoll.yml; then
      print_message "NetIntel enrichment is active" "$GREEN"
    else
      print_message "NetIntel enrichment is not active" "$RED"
    fi

    print_message "********** Elasticsearch **********" "$NC"
    
    version=$(/usr/share/elasticsearch/bin/elasticsearch --version | grep -oP 'Version: \K[\d.]+')
    echo -e "Installed Elasticsearch version: $version\n"

    if systemctl is-active --quiet elasticsearch.service; then
      print_message "elasticsearch.service is running" "$GREEN"
    else
      print_message "elasticsearch.service is not running" "$RED"
    fi

     if journalctl -u elasticsearch.service | grep -iq "level=error"; then
      print_message "Errors found in elasticsearch.service logs:" "$RED"
      #journalctl -u elasticsearch.service | grep -i "level=error"
    else
      print_message "No errors found in elasticsearch.service logs" "$GREEN"
    fi

    if netstat -tuln | grep -q ":9200"; then
      print_message "Port 9200 is open" "$GREEN"
    else
      print_message "Port 9200 is not open" "$RED"
    fi

    curl_result=$(curl -s -k -u elastic:$elastic_password https://localhost:9200)
    search_text='cluster_name" : "elasticsearch'
    if echo "$curl_result" | grep -q "$search_text"; then
      print_message "Elastic is ready. Used authenticated curl." "$GREEN"
    else
      print_message "Something's wrong with Elastic..." "$RED"
      echo "$curl_result"
    fi

    print_message "************** Kibana *************" "$NC"
    version=$(/usr/share/kibana/bin/kibana --version --allow-root | jq -r '.config.serviceVersion.value' 2>/dev/null)
    echo -e "Installed Kibana version: $version\n"

    if systemctl is-active --quiet kibana.service; then
      print_message "kibana.service is running" "$GREEN"
    else
      print_message "kibana.service is not running" "$RED"
    fi

    if journalctl -u kibana.service | grep -iq "\[error\]"; then
      print_message "Errors found in kibana.service logs:" "$RED"
      #journalctl -u kibana.service | grep -i "\[error\]"
    else
      print_message "No errors found in kibana.service logs" "$GREEN"
    fi

    if netstat -tuln | grep -q ":5601"; then
      print_message "Port 5601 is open" "$GREEN"
    else
      print_message "Port 5601 is not open" "$RED"
    fi

    # Check Kibana status
    response=$(curl -s -X GET "http://$ip_address:5601/api/status")
    
    if [[ $response == *'"status":{"overall":{"level":"available"}}'* ]]; then
        print_message "Kibana is ready. Used curl" "$GREEN"
    else
        print_message "Kibana is not ready" "$RED"
        echo "$response"
    fi


    print_message "************* SNMPcoll ************" "$NC"
    
    version=$(/usr/share/elastiflow/bin/snmpcollcoll -version)
    echo -e "Installed ElastiFlow SNMP version: $version"
    version=$snmp_kibana_dashboards_version
    echo -e "Installed ElastiFlow SNMP Dashboards version: $snmp_kibana_dashboards_codex_ecs $version"

    verify_ef_snmp_configured_pw_for_elastic
    
    get_dashboard_url "ElastiFlow (telemetry): Overview"
    if [ "$dashboard_url" == "Dashboard not found" ]; then
      print_message "Dashboard URL: $dashboard_url" "$RED"
    else
      print_message "Dashboard URL: $dashboard_url" "$GREEN"
    fi

    if systemctl is-active --quiet snmpcoll.service; then
      print_message "snmpcoll.service is running" "$GREEN"
    else
      print_message "snmpcoll.service is not running" "$RED"
    fi

    if journalctl -u snmpcoll.service | grep -iq "level=error"; then
    print_message "Errors found in snmpcoll.service logs:" "$RED"
    #journalctl -u snmpcoll.service | grep -i "level=error"
  else
    print_message "No errors found in snmpcoll.service logs" "$GREEN"
  fi

    # Path to the snmpcoll.yml file
    snmpcoll_file="/etc/elastiflow/snmpcoll.yml"

    if [ -f "$snmpcoll_file" ]; then
      # Extract values from the snmpcoll.yml file
      ef_account_id=$(grep '^EF_ACCOUNT_ID: ' "$snmpcoll_file" | awk '{print $2}' | tr -d '"')
      ef_license_key=$(grep '^EF_LICENSE_KEY: ' "$snmpcoll_file" | awk '{print $2}' | tr -d '"')
      ef_license_accepted=$(grep '^EF_LICENSE_ACCEPTED: ' "$snmpcoll_file" | awk '{print $2}' | tr -d '"')
    fi

    if [ -n "$ef_account_id" ] && [ -n "$ef_license_key" ] && [ "$ef_license_accepted" == "true" ]; then
      print_message "EF_LICENSE_ACCEPTED: $ef_license_accepted, EF_ACCOUNT_ID: $ef_account_id, EF_LICENSE_KEY: $ef_license_key" "$GREEN"
    else
      print_message "ElastiFlow account ID, license key, or license accepted is not correctly configured" "$RED"
    fi

    print_message "************************************" "$NC"

  } | tee "$output_file"
}


get_host_ip() {
  INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(docker|lo)' | head -n 1)
  if [ -z "$INTERFACE" ]; then
    echo "No suitable network interface found."
    return 1
  else
    ip_address=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}' | cut -d/ -f1)
    if [ -z "$ip_address" ]; then
      echo "No IP address found for interface $INTERFACE."
      return 1
    else
      return 0
    fi
  fi
}


get_dashboard_url() {
  
  get_host_ip
  local kibana_url="http://$ip_address:5601"
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$flow_config_path" | awk -F"'" '{print $2}')
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  local response=$(curl -s -u "$elastic_username:$elastic_password" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
  local dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  if [ -z "$dashboard_id" ]; then
    dashboard_url="Dashboard not found"
  else
    dashboard_url="$kibana_url/app/kibana#/dashboard/$dashboard_id"
  fi
}


comment_and_add_line() {
  local FILE=$1
  local FIND=$2
  local REPLACE=$3

  FIND_ESCAPED=$(echo "$FIND" | sed 's/[.[\*^$]/\\&/g')
  REPLACE_ESCAPED=$(echo "$REPLACE" | sed 's/[&/\]/\\&/g')

  if grep -q "^#\?$FIND_ESCAPED" "$FILE"; then
    existing_line=$(grep "^#\?$FIND_ESCAPED" "$FILE")
    sed -i.bak "/^#\?$FIND_ESCAPED/c\\$REPLACE" "$FILE"
    print_message "Replaced existing line '$existing_line' with '$REPLACE'." "$GREEN"
  else
    if grep -q "^#ElastiFlow PoC Configurator" "$FILE"; then
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added '$REPLACE' under the heading '#ElastiFlow PoC Configurator'." "$GREEN"
    else
      print_message "Heading '#ElastiFlow PoC Configurator' not found in the file. Adding the heading to the file." "$RED"
      echo -e "\n#ElastiFlow PoC Configurator" | tee -a "$FILE" > /dev/null
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added '$REPLACE' under the newly added heading '#ElastiFlow PoC Configurator'." "$GREEN"
    fi
  fi
}

find_and_replace() {
  local FILE=$1
  shift
  local PAIRS=("$@")

  if [ ! -f "$FILE" ]; then
    print_message "File not found!" "$RED"
    exit 1
  fi

  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    local FIND=${PAIRS[i]}
    local REPLACE=${PAIRS[i+1]}
    comment_and_add_line "$FILE" "$FIND" "$REPLACE"
  done

  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    local REPLACE=${PAIRS[i+1]}
    if grep -qF "$REPLACE" "$FILE"; then
      print_message "Verified: '$REPLACE' is in the file." "$GREEN"
    else
      print_message "Verification failed: '$REPLACE' is not in the file." "$RED"
    fi
  done
}

reload_and_restart_services() {
  local services=("$@")
  printf "Performing daemon-reload\n"
  systemctl daemon-reload
  for service in "${services[@]}"; do
    echo "Restarting service: $service"
    systemctl restart "$service"
    echo "done"
  done
}


check_service_health() {
  print_message "Checking if flowcoll.service stays running for at least 10 seconds..." "$GREEN"
  sleep 10
  if ! systemctl is-active --quiet flowcoll.service; then
    print_message "flowcoll.service did not stay started." "$RED"
    if journalctl -u flowcoll.service | grep -q "license error"; then
      print_message "License error found in logs. Exiting to main menu." "$RED"
      restore_latest_backup
      reload_and_restart_services "flowcoll.service"
    else
      restore_latest_backup
      reload_and_restart_services "flowcoll.service"
      print_message "Rerunning the configuration routine." "$GREEN"
    fi
    return 1
  else
    print_message "flowcoll.service restarted successfully and stayed running for at least 10 seconds." "$GREEN"
    return 0
  fi
}

backup_existing_flowcoll() {
  FILE_PATH=/etc/elastiflow/flowcoll.yml
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  if [ -f $FILE_PATH ]; then
    cp -f $FILE_PATH ${FILE_PATH}.bak.$TIMESTAMP
    print_message "Backed up the existing $FILE_PATH to ${FILE_PATH}.bak.$TIMESTAMP." "$GREEN"
  fi
}

restore_latest_backup() {
  FILE_PATH=/etc/elastiflow/flowcoll.yml
  LATEST_BACKUP=$(ls -t ${FILE_PATH}.bak.* 2>/dev/null | head -1)
  if [ -f $LATEST_BACKUP ]; then
    cp -f $LATEST_BACKUP $FILE_PATH
    print_message "Restored $FILE_PATH from the latest backup: $LATEST_BACKUP." "$GREEN"
  else
    print_message "No backup found." "$RED"
  fi
}

download_default_conf() {
  wget -P /tmp -O flow-collector_"$flow_collector_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$flow_collector_version"_linux_amd64.deb
  dpkg-deb -xv flow-collector_"$flow_collector_version"_linux_amd64.deb /tmp/elastiflow > /dev/null
  mkdir -p /etc/elastiflow/
  cp /tmp/elastiflow/etc/elastiflow/flowcoll.yml /etc/elastiflow/
  rm -rf /tmp/elastiflow
  print_message "Default flowcoll.yml downloaded and copied." "$GREEN"
}

configure_trial() {
  FILE_PATH=/etc/elastiflow/flowcoll.yml
  if [ ! -f $FILE_PATH ]; then
    print_message "$FILE_PATH not found. Downloading default configuration." "$RED"
    download_default_conf
  fi
  show_trial

  ef_account_id=$(grep '^EF_ACCOUNT_ID: ' $FILE_PATH | awk '{print $2}' | tr -d '"')
  ef_license_key=$(grep '^EF_LICENSE_KEY: ' $FILE_PATH | awk '{print $2}' | tr -d '"')

 while true; do
    read -p "Enter your ElastiFlow account ID (or 'q' to quit): " elastiflow_account_id
    if [[ $elastiflow_account_id == "q" ]]; then
      return
    elif [[ -z $elastiflow_account_id ]]; then
      print_message "ElastiFlow account ID cannot be empty. Please enter a valid ID." "$RED"
    else
      break
    fi
  done

  while true; do
    read -p "Enter your ElastiFlow license key (or 'q' to quit): " ef_license_key
    if [[ $ef_license_key == "q" ]]; then
      return
    elif [[ -z $ef_license_key ]]; then
      print_message "ElastiFlow license key cannot be empty. Please enter a valid key." "$RED"
    else
      break
    fi
  done

  STRINGS_TO_REPLACE=(
    "EF_LICENSE_ACCEPTED" "EF_LICENSE_ACCEPTED: \"true\""
    "EF_ACCOUNT_ID" "EF_ACCOUNT_ID: \"${elastiflow_account_id}\""
    "EF_LICENSE_KEY" "EF_LICENSE_KEY: \"${ef_license_key}\""
  )

  backup_existing_flowcoll
  find_and_replace "$FILE_PATH" "${STRINGS_TO_REPLACE[@]}"
  reload_and_restart_services "flowcoll.service"
  if check_service_health configure_trial; then
    print_message "Fully featured trial enabled with the provided ElastiFlow account ID and license key." "$GREEN"
  else
    print_message "Failed to enable fully featured trial. Changes reverted. Returning to main menu." "$RED"
  fi

#start_elasticsearch_trial
}

start_elasticsearch_trial() {
  # Extract the Elasticsearch password from the configuration file
  elastic_password=$(grep "^EF_OUTPUT_ELASTICSEARCH_PASSWORD: '" "$flow_config_path" | awk -F"'" '{print $2}')
  
  # Run the curl command and capture the output
  curl_result=$(curl -s -k -u "$elastic_username:$elastic_password" -X POST "https://localhost:9200/_license/start_trial?acknowledge=true&pretty")

}


configure_maxmind() {
  FILE_PATH=/etc/elastiflow/flowcoll.yml
  show_maxmind

  maxmind_asn_configured=$(grep -q '^EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: ' $FILE_PATH && echo "yes" || echo "no")
  maxmind_geoip_configured=$(grep -q '^EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: ' $FILE_PATH && echo "yes" || echo "no")

  if [ "$maxmind_asn_configured" == "yes" ] || [ "$maxmind_geoip_configured" == "yes" ]; then
    print_message "MaxMind ASN and/or GeoIP enrichment fields are already configured." "$RED"
    read -p "Do you want to overwrite the existing values? (y/n): " overwrite_choice
    if [[ $overwrite_choice != "y" ]]; then
      return
    fi
  fi

  read -p "Enter your MaxMind license key (or 'q' to quit): " maxmind_license_key
  if [[ $maxmind_license_key == "q" ]]; then
    return
  fi

  mkdir -p /etc/elastiflow/maxmind/

  asn_download_success=false
  geoip_download_success=false

  if wget -O ./Geolite2-ASN.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=$maxmind_license_key&suffix=tar.gz"; then
    tar -xvzf Geolite2-ASN.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/
    rm -f ./Geolite2-ASN.tar.gz
    print_message "MaxMind ASN database downloaded and extracted successfully." "$GREEN"
    asn_download_success=true
  else
    print_message "Failed to download MaxMind ASN database." "$RED"
  fi

  if wget -O ./Geolite2-City.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$maxmind_license_key&suffix=tar.gz"; then
    tar -xvzf Geolite2-City.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/
    rm -f ./Geolite2-City.tar.gz
    print_message "MaxMind GeoIP City database downloaded and extracted successfully." "$GREEN"
    geoip_download_success=true
  else
    print_message "Failed to download MaxMind GeoIP City database." "$RED"
  fi

  if ! $asn_download_success || ! $geoip_download_success; then
    read -p "One or both downloads failed. Do you still want to add the configuration settings to flowcoll.yml? (y/n): " add_config_choice
    if [[ $add_config_choice != "y" ]]; then
      return
    fi
  fi

  STRINGS_TO_REPLACE=(
    "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: \"true\""
    "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH" "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH: \"/etc/elastiflow/maxmind/GeoLite2-ASN.mmdb\""
    "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: \"true\""
    "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH" "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH: \"/etc/elastiflow/maxmind/GeoLite2-City.mmdb\""
    "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES" "EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES: city,country,country_code,location,timezone"
  )

  backup_existing_flowcoll
  find_and_replace "$FILE_PATH" "${STRINGS_TO_REPLACE[@]}"

  if $asn_download_success && $geoip_download_success; then
    reload_and_restart_services "flowcoll.service"
    if check_service_health configure_maxmind; then
      print_message "MaxMind ASN and Geo enrichment enabled with the provided license key." "$GREEN"
    else
      print_message "Failed to enable MaxMind ASN and Geo enrichment. Changes reverted. Returning to main menu." "$RED"
    fi
  else
    print_message "Configuration settings added to flowcoll.yml but flowcoll service was not restarted due to download failures." "$YELLOW"
  fi
}


validate_cidr() {
  local cidr=$1
  local valid=1
  if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}\/([0-9]{1,2})$ ]]; then
    local IFS=.
    ip=(${cidr%%/*})
    prefix=${cidr##*/}
    for i in {0..3}; do
      if [[ ${ip[$i]} -gt 255 ]]; then
        valid=0
      fi
    done
    if [[ $prefix -gt 32 ]]; then
      valid=0
    fi
  else
    valid=0
  fi
  echo $valid
}

validate_ip() {
  local ip=$1
  local valid=1
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    local IFS=.
    ip=($ip)
    for i in {0..3}; do
      if [[ ${ip[$i]} -gt 255 ]]; then
        valid=0
      fi
    done
  else
    valid=0
  fi
  echo $valid
}

configure_static_ip() {
  clear
  echo "Available network interfaces:"
  interfaces=($(ip link show | awk -F: '$1 ~ /^[0-9]+$/ && $2 !~ /^ lo|^ docker/ {print $2}' | sed 's/ //g'))
  for i in "${!interfaces[@]}"; do
    echo "$((i+1)). ${interfaces[$i]}"
  done

  while true; do
    read -p "Enter the number corresponding to the interface you want to configure (or 'q' to quit): " interface_number
    if [[ $interface_number == "q" ]]; then
      return
    fi
    if [[ $interface_number -ge 1 && $interface_number -le ${#interfaces[@]} ]]; then
      interface=${interfaces[$((interface_number-1))]}
      break
    else
      print_message "Invalid selection. Please choose a valid interface number." "$RED"
    fi
  done

  ip link set $interface up

  while true; do
    read -p "Enter IP address (CIDR format, e.g., 192.168.1.100/24) (or 'q' to quit): " ip_address
    if [[ $ip_address == "q" ]]; then
      return
    fi
    if [[ $(validate_cidr $ip_address) -eq 1 ]]; then
      break
    else
      print_message "Invalid IP address format. Please enter a valid IP address in CIDR format." "$RED"
    fi
  done

  read -p "Enter default gateway (optional, or 'q' to quit): " default_gateway
  if [[ $default_gateway == "q" ]]; then
    return
  fi
  if [[ -n "$default_gateway" && $(validate_ip $default_gateway) -eq 0 ]]; then
    print_message "Invalid gateway address format. Please enter a valid IP address." "$RED"
    return
  fi

  read -p "Enter DNS servers (comma separated, optional, or 'q' to quit): " dns_servers
  if [[ $dns_servers == "q" ]]; then
    return
  fi
  if [[ -n "$dns_servers" ]]; then
    IFS=',' read -r -a dns_array <<< "$dns_servers"
    for dns in "${dns_array[@]}"; do
      if [[ $(validate_ip $dns) -eq 0 ]]; then
        print_message "Invalid DNS server address format. Please enter valid IP addresses." "$RED"
        return
      fi
    done
  fi

  print_message "Configuration:" "$GREEN"
  echo "Interface: $interface"
  echo "IP address: $ip_address"
  echo "Default gateway: ${default_gateway:-None}"
  echo "DNS servers: ${dns_servers:-None}"
  read -p "Do you want to apply these settings? (y/n): " confirm
  if [[ $confirm != "y" ]]; then
    echo "Discarding changes."
    return
  fi

  netplan_file=$(find /etc/netplan -name "*.yaml" | head -n 1)
  cp $netplan_file ${netplan_file}.bak.$(date +%Y%m%d%H%M%S)
  tee $netplan_file > /dev/null <<EOL
network:
  version: 2
  ethernets:
    $interface:
      addresses:
        - $ip_address
EOL

  if [ -n "$default_gateway" ]; then
    tee -a $netplan_file > /dev/null <<EOL
      routes:
        - to: default
          via: $default_gateway
EOL
  fi

  if [ -n "$dns_servers" ]; then
    tee -a $netplan_file > /dev/null <<EOL
      nameservers:
        addresses: [$dns_servers]
EOL
  fi

  netplan apply
  print_message "Static IP address configuration applied successfully." "$GREEN"
}

revert_network_changes() {
  clear
  backups=($(ls /etc/netplan/*.bak.* 2>/dev/null))
  if [ ${#backups[@]} -eq 0 ]; then
    print_message "No network configuration backups found." "$RED"
    return
  fi

  echo "Available backups:"
  for i in "${!backups[@]}"; do
    echo "$((i+1)). ${backups[$i]}"
  done

  while true; do
    read -p "Enter the number corresponding to the backup you want to restore: " backup_number
    if [[ $backup_number -ge 1 && $backup_number -le ${#backups[@]} ]]; then
      backup=${backups[$((backup_number-1))]}
      break
    else
      print_message "Invalid selection. Please choose a valid backup number." "$RED"
    fi
  done

  cp $backup /etc/netplan/$(basename $backup | sed 's/.bak.*//')
  netplan apply
  print_message "Network configuration reverted successfully." "$GREEN"
}

capture_packets() {
  clear
  if pgrep tcpdump > /dev/null; then
    print_message "Packet capture is currently running." "$RED"
    read -p "Do you want to terminate the packet capture? (y/n): " terminate_choice
    if [[ $terminate_choice == "y" ]]; then
      pkill tcpdump
      print_message "Packet capture terminated." "$GREEN"
    fi
    return
  fi

  if ! command -v tcpdump &> /dev/null; then
    apt-get update
    apt-get install -y tcpdump
  fi

  echo "Available network interfaces:"
  interfaces=($(ip link show | awk -F: '$1 ~ /^[0-9]+$/ && $2 !~ /^ lo|^ docker/ {print $2}' | sed 's/ //g'))
  for i in "${!interfaces[@]}"; do
    echo "$((i+1)). ${interfaces[$i]}"
  done

  while true; do
    read -p "Enter the number corresponding to the interface you want to monitor (or 'q' to quit): " interface_number
    if [[ $interface_number == "q" ]]; then
      return
    fi
    if [[ $interface_number -ge 1 && $interface_number -le ${#interfaces[@]} ]]; then
      interface=${interfaces[$((interface_number-1))]}
      break
    else
      print_message "Invalid selection. Please choose a valid interface number." "$RED"
    fi
  done

  while true; do
    read -p "Do you want to capture by duration (d) or by packet count (p)? (or 'q' to quit): " capture_choice
    if [[ $capture_choice == "q" ]]; then
      return
    elif [[ $capture_choice == "d" ]]; then
      while true; do
        read -p "Enter the duration for packet capture in seconds (or 'q' to quit): " duration
        if [[ $duration == "q" ]]; then
          return
        elif [[ ! $duration =~ ^[0-9]+$ ]]; then
          print_message "Invalid duration. Please enter a valid number of seconds." "$RED"
        else
          break
        fi
      done
      break
    elif [[ $capture_choice == "p" ]]; then
      while true; do
        read -p "Enter the number of packets to capture (or 'q' to quit): " packet_count
        if [[ $packet_count == "q" ]]; then
          return
        elif [[ ! $packet_count =~ ^[0-9]+$ ]]; then
          print_message "Invalid packet count. Please enter a valid number of packets." "$RED"
        else
          break
        fi
      done
      break
    else
      print_message "Invalid choice. Please enter 'd' for duration or 'p' for packet count." "$RED"
    fi
  done

  while true; do
    read -p "Enter the destination port to filter for (default is 9995, enter 'A' for all ports, or 'q' to quit): " port
    if [[ $port == "q" ]]; then
      return
    elif [[ -z "$port" ]]; then
      port=9995
      break
    elif [[ $port == "A" || $port =~ ^[0-9]+$ ]]; then
      break
    else
      print_message "Invalid port. Please enter a valid port number, 'A' for all ports, or leave blank for default port 9995." "$RED"
    fi
  done

  timestamp=$(date +%Y%m%d%H%M%S)
  capture_file="capture_$timestamp.pcap"
  capture_path="$(pwd)/$capture_file"

  if [[ $capture_choice == "d" ]]; then
    if [[ $port == "A" ]]; then
      tcpdump -i $interface -w "$capture_path" -G $duration -W 1
    else
      tcpdump -i $interface dst port $port -w "$capture_path" -G $duration -W 1
    fi
  elif [[ $capture_choice == "p" ]]; then
    if [[ $port == "A" ]]; then
      tcpdump -i $interface -w "$capture_path" -c $packet_count
    else
      tcpdump -i $interface dst port $port -w "$capture_path" -c $packet_count
    fi
  fi

  print_message "Packet capture completed. File saved as $capture_path." "$GREEN"
}

generate_sample_flow() {
  clear
  print_message "Generating sample flow..." "$GREEN"

  if ! command -v docker &> /dev/null; then
    install_docker
  else
    echo "Docker is already installed."
  fi

  get_host_ip

  docker run -it --rm networkstatic/nflow-generator -t $ip_address -p 9995
}

install_flow_generator() {
  clear
  if command -v pmacctd &> /dev/null; then
    print_message "pmacct is already installed." "$GREEN"
    if pgrep pmacctd > /dev/null; then
      print_message "pmacct is currently running." "$RED"
      read -p "Do you want to terminate pmacct? (y/n): " terminate_choice
      if [[ $terminate_choice == "y" ]]; then
        pkill pmacctd
        print_message "pmacct terminated." "$GREEN"
      else
        return
      fi
    else
      print_message "pmacct is not running." "$RED"
      read -p "Do you want to start pmacct? (y/n): " start_choice
      if [[ $start_choice == "y" ]]; then
        pmacctd -f /etc/pmacct/pmacctd.conf
        print_message "pmacct started." "$GREEN"
        return
      else
        return
      fi
    fi
  else
    apt-get update
    apt-get install -y pmacct
    if command -v pmacctd &> /dev/null; then
      print_message "pmacct installed successfully." "$GREEN"
    else
      print_message "pmacct installation failed." "$RED"
      return
    fi
  fi

  echo "Available network interfaces:"
  interfaces=($(ip link show | awk -F: '$1 ~ /^[0-9]+$/ && $2 !~ /^ lo|^ docker/ {print $2}' | sed 's/ //g'))
  for i in "${!interfaces[@]}"; do
    echo "$((i+1)). ${interfaces[$i]}"
  done

  while true; do
    read -p "Enter the number corresponding to the interface you want to monitor: " interface_number
    if [[ $interface_number == "q" ]]; then
      return
    fi
    if [[ $interface_number -ge 1 && $interface_number -le ${#interfaces[@]} ]]; then
      interface=${interfaces[$((interface_number-1))]}
      break
    else
      print_message "Invalid selection. Please choose a valid interface number." "$RED"
    fi
  done

  tee /etc/pmacct/pmacctd.conf > /dev/null <<EOL
daemonize: false
pcap_interface: $interface
aggregate: src_mac, dst_mac, src_host, dst_host, src_port, dst_port, proto, tos
plugins: nfprobe, print
nfprobe_receiver: 127.0.0.1:9995
! nfprobe_receiver: [FD00::2]:2100
nfprobe_version: 9
! nfprobe_engine: 1:1
nfprobe_timeouts: tcp=15:maxlife=1800
!
! networks_file: /path/to/networks.lst
!...
EOL

  pmacctd -f /etc/pmacct/pmacctd.conf
  print_message "Flow generator installed and running." "$GREEN"
}

monitor_fps() {
  clear
  local file_path=/etc/elastiflow/flowcoll.yml

  if grep -q '^EF_OUTPUT_MONITOR_ENABLE: "true"' "$file_path"; then
    print_message "Disabling FPS monitoring..." "$GREEN"
    sed -i '/^EF_OUTPUT_MONITOR_ENABLE: "true"/c\EF_OUTPUT_MONITOR_ENABLE: "false"' "$file_path"
    print_message "FPS monitoring disabled." "$GREEN"
    reload_and_restart_services "flowcoll.service"
    return
  else
    while true; do
      read -p "Enter bytes per record (default is 250): " bytes_per_document
      if [[ -z "$bytes_per_document" || "$bytes_per_document" =~ ^[0-9]+$ ]]; then
        bytes_per_document=${bytes_per_document:-250}
        break
      else
        echo "Invalid input. Please enter a number."
      fi
    done

    while true; do
      read -p "Enter monitoring interval in seconds (default is 300): " EF_OUTPUT_MONITOR_INTERVAL
      if [[ -z "$EF_OUTPUT_MONITOR_INTERVAL" || "$EF_OUTPUT_MONITOR_INTERVAL" =~ ^[0-9]+$ ]]; then
        EF_OUTPUT_MONITOR_INTERVAL=${EF_OUTPUT_MONITOR_INTERVAL:-300}
        break
      else
        echo "Invalid input. Please enter a number."
      fi
    done

    print_message "Enabling FPS monitoring..." "$GREEN"
    comment_and_add_line "$file_path" "EF_OUTPUT_MONITOR_ENABLE" 'EF_OUTPUT_MONITOR_ENABLE: "true"'
    comment_and_add_line "$file_path" "EF_OUTPUT_MONITOR_INTERVAL" "EF_OUTPUT_MONITOR_INTERVAL: $EF_OUTPUT_MONITOR_INTERVAL"
    print_message "FPS monitoring enabled." "$GREEN"
    reload_and_restart_services "flowcoll.service"
  fi

  print_message "Monitoring FPS..." "$GREEN"
  print_message "Assumptions: $bytes_per_document bytes per record." "$GREEN"
  print_message "Monitoring interval: $EF_OUTPUT_MONITOR_INTERVAL seconds ($((EF_OUTPUT_MONITOR_INTERVAL / 60)) minutes)." "$GREEN"

  while true; do
    journalctl -u flowcoll.service -f | grep --line-buffered "Monitor Output: decoding rate:" | while read -r line; do
      raw_timestamp=$(echo "$line" | grep -oP '(?<=ts":")[^"]+')
      local_time=$(date '+%Y-%m-%d %H:%M:%S')
      records_per_second=$(echo "$line" | grep -oP '(?<=decoding rate: )\d+')
      if [ -n "$records_per_second" ] && [ "$records_per_second" -ne 0 ]; then
        storage_capacity_gb=500
        documents_per_day=$((records_per_second * 60 * 60 * 24))
        storage_capacity_bytes=$((storage_capacity_gb * 1024 * 1024 * 1024))
        days_of_storage=$(echo "$storage_capacity_bytes / ($documents_per_day * $bytes_per_document)" | bc)
        echo "[$local_time] [$raw_timestamp] Records per second: $records_per_second, Days of storage in 500 GB: $days_of_storage"
      else
        echo "[$local_time] [$raw_timestamp] Records per second: $records_per_second, Unable to calculate days of storage due to zero records per second."
      fi
    done
    read -t 1 -n 1 key
    if [[ $key == "q" ]]; then
      break
    fi
  done
}

play_battleship() {
  clear
  declare -A board
  ships=("Aircraft Carrier" "Battleship" "Submarine" "Destroyer" "Patrol Boat")
  ship_sizes=(5 4 3 3 2)
  board_size=10

  for ((i = 0; i < board_size; i++)); do
    for ((j = 0; j < board_size; j++)); do
      board[$i,$j]="~"
    done
  done

  display_board() {
    echo "  0 1 2 3 4 5 6 7 8 9"
    for ((i = 0; i < board_size; i++)); do
      echo -n "$i "
      for ((j = 0; j < board_size; j++)); do
        echo -n "${board[$i,$j]} "
      done
      echo
    done
  }

  place_ships() {
    for ((s = 0; s < ${#ships[@]}; s++)); do
      local size=${ship_sizes[$s]}
      local placed=0

      while [[ $placed -eq 0 ]]; do
        local orientation=$((RANDOM % 2))
        local row=$((RANDOM % board_size))
        local col=$((RANDOM % board_size))
        local fits=1

        if [[ $orientation -eq 0 ]]; then
          if ((col + size <= board_size)); then
            for ((i = 0; i < size; i++)); do
              if [[ ${board[$row,$((col + i))]} != "~" ]]; then
                fits=0
                break
              fi
            done
            if [[ $fits -eq 1 ]]; then
              for ((i = 0; i < size; i++)); do
                board[$row,$((col + i))]="${ships[$s]:0:1}"
              done
              placed=1
            fi
          fi
        else
          if ((row + size <= board_size)); then
            for ((i = 0; i < size; i++)); do
              if [[ ${board[$((row + i)),$col]} != "~" ]]; then
                fits=0
                break
              fi
            done
            if [[ $fits -eq 1 ]]; then
              for ((i = 0; i < size; i++)); do
                board[$((row + i)),$col]="${ships[$s]:0:1}"
              done
              placed=1
            fi
          fi
        fi
      done
    done
  }

  check_hit() {
    local row=$1
    local col=$2
    if [[ ${board[$row,$col]} =~ [ABS] ]]; then
      board[$row,$col]="X"
      echo "Hit!"
    else
      board[$row,$col]="O"
      echo "Miss!"
    fi
  }

  place_ships

  while true; do
    display_board
    echo "Enter your move (row and column) or 'q' to quit: "
    read row col
    if [[ $row == "q" || $col == "q" ]]; then
      break
    elif [[ $row =~ ^[0-9]$ && $col =~ ^[0-9]$ ]]; then
      check_hit $row $col
    else
      echo "Invalid move. Please enter a valid row and column."
    fi
  done

  echo "Game over!"
}

reconfigure_jvm_memory() {
  print_message "Configuring JVM memory usage..." "$GREEN"
  total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  one_third_mem_gb=$(echo "$total_mem_kb / 1024 / 1024 / 3" | bc -l)
  rounded_mem_gb=$(printf "%.0f" $one_third_mem_gb)
  if [ $rounded_mem_gb -gt 31 ]; then
    jvm_mem_gb=31
  else
    jvm_mem_gb=$rounded_mem_gb
  fi
  jvm_options="-Xms${jvm_mem_gb}g\n-Xmx${jvm_mem_gb}g"
  echo -e $jvm_options | tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null
  print_message "Elasticsearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx." "$GREEN"
}

show_intro() {
  print_message "***********************************" "$GREEN"
  print_message "*** ElastiFlow PoC Configurator ***" "$GREEN"
  print_message "***********************************" "$GREEN"
}

show_trial() {
  print_message "********** Configure Trial********" "$GREEN"
  print_message "Obtain ElastiFlow trial credentials from: https://elastiflow.com/get-started" "$GREEN"
  print_message "**********************************" "$GREEN"
}

show_maxmind() {
  print_message "** Configure MaxMind Enrichment **" "$GREEN"
  print_message "Obtain Maxmind license key from: https://www.maxmind.com/en/geolite2/signup" "$GREEN"
  print_message "Log in to Maxmind.com, click 'My Account', and then 'Manage License Keys'" "$GREEN"
  print_message "**********************************" "$GREEN"
}

check_for_updates
which_search_engine
while true; do
  show_intro
  echo "Choose an option:"
  echo "1. Configure static IP address"
  echo "2. Configure fully featured trial"
  echo "3. Enable MaxMind enrichment"
  echo "4. ElastiFlow Utilities"
  echo "5. Elasticsearch Utilities"
  echo "6. Opensearch Utilities"
  echo "7. Generate support bundle"
  echo "8. Change Elasticsearch password"
  echo "9. Quit"
  read -p "Enter your choice (1-8): " choice
  clear
  case $choice in
    1)
      configure_static_ip
      ;;
    2)
      configure_trial
      ;;
    3)
      configure_maxmind
      ;;
    4)
      while true; do
        echo "Utilities:"
        echo "1. Capture packets"
        echo "2. Daemon reload and restart flowcoll.service"
        echo "4. Edit flowcoll.yml using nano"
        echo "5. Enable FPS monitor"
        echo "6. Generate sample flow"
        echo "7. Health check"
        echo "8. Install/Uninstall flow generator (pmacct)"
        echo "9. Reconfigure JVM memory usage"
        echo "10. Restore flowcoll.yml from Internet"
        echo "11. Restore flowcoll.yml from latest backup"
        echo "12. Revert network interface changes"
        echo "14. Watch flowcoll.service log"
        echo "16. Install SNMP Collector"
        echo "18. Update ElastiFlow Flow Collector"
        echo "19. Update ElastiFlow SNMP Collector"
        echo "20. Back"
        read -p "Enter your choice (1-19): " utility_choice
        clear
        case $utility_choice in
          1)
            capture_packets
            ;;
          2)
            reload_and_restart_services "flowcoll.service"
            ;;
          4)
            backup_existing_flowcoll
            nano /etc/elastiflow/flowcoll.yml
            latest_backup=$(ls -t /etc/elastiflow/flowcoll.yml.bak.* 2>/dev/null | head -1)
            if ! diff -q /etc/elastiflow/flowcoll.yml "$latest_backup"; then
              read -p "Do you want to reload and restart flowcoll.service? (y/n): " reload_choice
              if [[ $reload_choice == "y" ]]; then
                reload_and_restart_services "flowcoll.service"
                check_service_health
              fi
            fi
            ;;
          5)
            monitor_fps
            ;;
          6)
            generate_sample_flow
            ;;
          7)
            perform_health_check
            ;;
          8)
            install_flow_generator
            ;;
          9)
            reconfigure_jvm_memory
            read -p "Do you want to reload and restart elasticsearch.service and kibana.service? (y/n): " reload_choice
            if [[ $reload_choice == "y" ]]; then
              reload_and_restart_services "elasticsearch.service" "kibana.service"
            fi
            ;;
          10)
            download_default_conf
            read -p "Do you want to reload and restart flowcoll.service? (y/n): " reload_choice
            if [[ $reload_choice == "y" ]]; then
              reload_and_restart_services "flowcoll.service"
              check_service_health
            fi
            ;;
          11)
            restore_latest_backup
            read -p "Do you want to reload and restart flowcoll.service? (y/n): " reload_choice
            if [[ $reload_choice == "y" ]]; then
              reload_and_restart_services "flowcoll.service"
              check_service_health
            fi
            ;;
          12)
            revert_network_changes
            ;;
          14)
            journalctl -u flowcoll.service -f
            ;;
          16)
            install_snmp_collector
            ;;
          18)
            update_flow_collector
            ;;
          19)
            update_snmp_collector
            ;;
          20)
            break
            ;;
          *)
            print_message "Invalid choice. Please enter a number between 1 and 20." "$RED"
            ;;
        esac
      done
      ;;
    5)
      if [[ $SEARCH_ENGINE == "Elastic" ]]; then
        while true; do
          echo "Easticsearch Utilities"
          echo "1. Daemon reload and restart flowcoll.service, elasticsearch.service, and kibana.service"
          echo "2. Watch elasticsearch.service log"
          echo "3. Watch kibana.service log"
          echo "4. Reset Elasticsearch password"
          echo "5. Back"
          read -p "Enter your choice (1-5): " game_choice
          clear
          case $game_choice in
            1)
              reload_and_restart_services "elasticsearch.service" "kibana.service" "flowcoll.service"
              ;;
            2)
              journalctl -u elasticsearch.service -f
              ;;
            3)
              journalctl -u kibana.service -f
              ;;
            4)
              reset_elastic_password
              ;;
            5)
              break
              ;;
            *)
              print_message "Invalid choice. Please enter 1-4." "$RED"
              ;;
          esac
        done
      else
        echo "Elasticsearch is not running...."
      fi
      ;;
    6)
      if [[ $SEARCH_ENGINE == "Opensearch" ]]; then
        while true; do
          echo "Opensearch Utilities"
          echo "1. Daemon reload and restart flowcoll.service, opensearch.service, and opensearch-dashboards.service"
          echo "2. Watch opensearch.service log"
          echo "3. Watch opensearch-dashboards.service log"
          echo "4. Reset Opensearch password"
          echo "5. Back"
          read -p "Enter your choice (1-5): " game_choice
          clear
          case $game_choice in
            1)
              reload_and_restart_services "opensearch.service" "opensearch-dashboards.service" "flowcoll.service"
              ;;
            2)
              journalctl -u opensearch.service -f
              ;;
            3)
              journalctl -u opensearch-dashboards.service -f
              ;;
            4)
              reset_opensearch_password
              ;;
            5)
              break
              ;;
            *)
              print_message "Invalid choice. Please enter 1-4." "$RED"
              ;;
          esac
        done
      else
        echo "Opensearch is not running...."
      fi
      ;;
    7)
      echo "Generating support bundle..."
      /usr/share/elastiflow/bin/flowcoll -s
      echo "Support bundle created"
      echo "Attach the resulting support bundle archive to an email or support ticket for ElastiFlow to review."
      ;;
    8)
      change_elasticsearch_password
      ;;
    9)
      echo "Quitting..."
      exit 0
      ;;
    *)
      print_message "Invalid choice. Please enter a number between 1 and 8." "$RED"
      ;;
  esac
done
