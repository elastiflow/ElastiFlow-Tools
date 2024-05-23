#!/bin/bash

# Version 1.3

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to reload systemd daemon and restart flowcoll service
reload_and_restart_flowcoll() {
  sudo systemctl daemon-reload
  sudo systemctl restart flowcoll.service
}

# Function to check the health of flowcoll.service and rerun the configuration if necessary
check_service_health() {
  echo "Checking if flowcoll.service stays running for at least 10 seconds..."
  i=10
  while [ $i -ge 1 ]; do
    echo -ne "Waiting: $i\033[0K\r"
    sleep 1
    i=$((i-1))
  done

  if ! sudo systemctl is-active --quiet flowcoll.service; then
    echo -e "${RED}flowcoll.service did not stay started.${NC}"
    
    # Check logs for "license error"
    if sudo journalctl -u flowcoll.service | grep -q "license error"; then
      echo -e "${RED}License error found in logs. Rerunning trial configuration.${NC}"
      configure_trial
      reload_and_restart_flowcoll
    else
      restore_latest_backup
      reload_and_restart_flowcoll
      echo "Rerunning the configuration routine."
      configure_trial
      reload_and_restart_flowcoll
    fi
    
    return 1
  else
    echo -e "${GREEN}flowcoll.service restarted successfully and stayed running for at least 10 seconds.${NC}"
    return 0
  fi
}

# Function to restore the latest backup of flowcoll.conf
restore_latest_backup() {
  FILE_PATH=/etc/systemd/system/flowcoll.service.d/flowcoll.conf
  LATEST_BACKUP=$(ls -t ${FILE_PATH}.bak.* | head -1)
  
  if [ -f $LATEST_BACKUP ]; then
    sudo cp -f $LATEST_BACKUP $FILE_PATH
    echo -e "${GREEN}Restored $FILE_PATH from the latest backup: $LATEST_BACKUP.${NC}"

  else
    echo -e "${RED}No backup file found to restore.${NC}"
  fi
}

# Function to configure ElastiFlow fully featured trial
configure_trial() {
  show_trial
  
  # Prompt for ElastiFlow account ID and license key
  read -p "Enter your ElastiFlow account ID: " account_id
  read -p "Enter your ElastiFlow license key: " license_key

  # Define the file path
  FILE_PATH=/etc/systemd/system/flowcoll.service.d/flowcoll.conf

  # Backup the existing configuration file with timestamp
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  sudo cp -f $FILE_PATH ${FILE_PATH}.bak.$TIMESTAMP

  # Delete existing lines for EF_LICENSE_ACCEPTED, EF_ACCOUNT_ID, and EF_FLOW_LICENSE_KEY
  sudo sed -i '/EF_LICENSE_ACCEPTED/d; /EF_ACCOUNT_ID/d; /EF_FLOW_LICENSE_KEY/d' $FILE_PATH

  # Add new configuration lines after the [Service] section
  sudo sed -i "/\[Service\]/a Environment=\"EF_LICENSE_ACCEPTED=true\"\nEnvironment=\"EF_ACCOUNT_ID=$account_id\"\nEnvironment=\"EF_FLOW_LICENSE_KEY=$license_key\"" $FILE_PATH

  # Reload and restart flowcoll service
  reload_and_restart_flowcoll

  # Check if flowcoll.service is active
  if check_service_health configure_trial; then
    echo -e "${GREEN}Fully featured trial enabled with the provided ElastiFlow account ID and license key.${NC}"
  fi
}

# Function to configure MaxMind ASN and Geo enrichment
configure_maxmind() {

  show_maxmind
  
  # Prompt for MaxMind license key
  read -p "Enter your MaxMind license key: " maxmind_license_key

  # Download and extract MaxMind databases
  sudo mkdir -p /etc/elastiflow/maxmind/
    
  if sudo wget -O ./Geolite2-ASN.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=$maxmind_license_key&suffix=tar.gz"; then
    sudo tar -xvzf Geolite2-ASN.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/
    sudo rm -f ./Geolite2-ASN.tar.gz
    echo "MaxMind ASN database downloaded and extracted successfully."
  else
    echo -e "${RED}Failed to download MaxMind ASN database. Rerunning the configuration routine.${NC}"
    configure_maxmind
    return 1
  fi

  if sudo wget -O ./Geolite2-City.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$maxmind_license_key&suffix=tar.gz"; then
    sudo tar -xvzf Geolite2-City.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/
    sudo rm -f ./Geolite2-City.tar.gz
    echo "MaxMind GeoIP City database downloaded and extracted successfully."
  else
    echo -e "${RED}Failed to download MaxMind GeoIP City database. Rerunning the configuration routine.${NC}"
    configure_maxmind
    return 1
  fi

  # Define the file path
  FILE_PATH=/etc/systemd/system/flowcoll.service.d/flowcoll.conf

  # Delete existing MaxMind lines
  sudo sed -i '/EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_LANG/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_INCLEXCL_PATH/d; /EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_INCLEXCL_REFRESH_RATE/d' $FILE_PATH

  # Add MaxMind heading if it does not exist and add new MaxMind configuration lines under the # MaxMind heading
  if ! grep -q "# MaxMind" $FILE_PATH; then
    echo "# MaxMind" | sudo tee -a $FILE_PATH
  fi

  sudo sed -i '/# Max Mind/ a Environment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE=true"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_PATH=/etc/elastiflow/maxmind/GeoLite2-ASN.mmdb"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE=true"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_PATH=/etc/elastiflow/maxmind/GeoLite2-City.mmdb"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_VALUES=city,country,country_code,location,timezone"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_LANG=en"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_INCLEXCL_PATH=/etc/elastiflow/maxmind/incl_excl.yml"\nEnvironment="EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_INCLEXCL_REFRESH_RATE=15"' $FILE_PATH

  # Reload and restart flowcoll service
  reload_and_restart_flowcoll

  # Check if flowcoll.service is active
  if check_service_health configure_maxmind; then
    echo -e "${GREEN}MaxMind ASN and Geo enrichment enabled with the provided license key.${NC}"
  fi
}

# Function to download default flowcoll.conf file from deb file
download_default_conf() {
  wget -O flow-collector.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_6.4.2_linux_amd64.deb
  dpkg-deb -xv flow-collector.deb /tmp/elastiflow > /dev/null
  sudo cp /tmp/elastiflow/etc/systemd/system/flowcoll.service.d/flowcoll.conf /etc/systemd/system/flowcoll.service.d/flowcoll.conf
  sudo rm -rf /tmp/elastiflow
  echo -e "${GREEN}Default flowcoll.conf downloaded and copied.${NC}"
}

show_intro() {
 echo -e "${GREEN}**********************************${NC}"
 echo -e "${GREEN}*** ElastiFlow PoC Configurator ***${NC}"
 echo -e "${GREEN}**********************************${NC}"
}

# Function to show instructions for requesting an account ID and license key
show_trial() {
 echo -e "${GREEN}********** Configure Trial********${NC}"
 echo -e "${GREEN}Obtain ElastiFlow trial credentials from: https://elastiflow.com/get-started${NC}"
 echo -e "${GREEN}**********************************${NC}"
}

# Function to show instructions for obtaining maxmind license key
show_maxmind() {
 echo -e "${GREEN}** Configure MaxMind Enrichment **${NC}"
 echo -e "${GREEN}Obtain Maxmind license key from: https://www.maxmind.com/en/geolite2/signup${NC}"
 echo -e "${GREEN}Log in to Maxmind.com, click "My Account", and then "Manage License Keys"${NC}"
 echo -e "${GREEN}**********************************${NC}"
}


# Main script execution

while true; do
  show_intro
  echo "Choose an option:"
  echo "1. Configure fully featured trial"
  echo "2. Enable MaxMind enrichment"
  echo "3. Restore flowcoll.conf from latest backup"
  echo "4. Download default flowcoll.conf from deb file"
  echo "5. Quit"
  read -p "Enter your choice (1-5): " choice
  case $choice in
    1)
      configure_trial
      ;;
    2)
      configure_maxmind
      ;;
    3)
      restore_latest_backup
      ;;
    4)
      download_default_conf
      ;;
    5)
      echo "Exiting the script."
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter a number between 1 and 5."
      ;;
  esac
done
