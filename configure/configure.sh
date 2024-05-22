# Version 1.2

#!/bin/bash

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
    echo "Restored $FILE_PATH from the latest backup: $LATEST_BACKUP."
  else
    echo -e "${RED}No backup file found to restore.${NC}"
  fi
}

# Function to configure ElastiFlow fully featured trial
configure_trial() {
  # Prompt the user to enable fully featured trial
  while true; do
    read -p "Do you want to install the fully featured trial? (yes/y or no/n): " enable_trial
    case $enable_trial in
      yes|y)
        enable_trial="yes"
        break
        ;;
      no|n)
        enable_trial="no"
        break
        ;;
      *)
        echo "Invalid input. Please enter yes/y or no/n."
        ;;
    esac
  done

  if [ "$enable_trial" = "yes" ]; then
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
  else
    echo "Fully featured trial not enabled."
  fi
}

# Function to configure MaxMind ASN and Geo enrichment
configure_maxmind() {
  # Prompt the user to enable MaxMind ASN and Geo enrichment
  while true; do
    read -p "Do you want to install MaxMind enrichment? (yes/y or no/n): " enable_maxmind
    case $enable_maxmind in
      yes|y)
        enable_maxmind="yes"
        break
        ;;
      no|n)
        enable_maxmind="no"
        break
        ;;
      *)
        echo "Invalid input. Please enter yes/y or no/n."
        ;;
    esac
  done

  if [ "$enable_maxmind" = "yes" ]; then
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
  else
    echo "MaxMind ASN and Geo enrichment not enabled."
  fi
}

# Function to restore flowcoll.conf to its original state
restore_original() {
  FILE_PATH=/etc/systemd/system/flowcoll.service.d/flowcoll.conf

  if [ -f ${FILE_PATH}.bak ]; then
    sudo cp -f ${FILE_PATH}.bak $FILE_PATH
    echo "flowcoll.conf restored to its original state."
  else
    echo -e "${RED}No backup file found to restore.${NC}"
  fi
}

# Function to show instructions for requesting an account ID and license key
show_intro() {
 echo -e "${GREEN}******************************${NC}"
 echo -e "${GREEN}***ElastiFlow PoC Configurator***${NC}"
 echo -e "${GREEN}******************************${NC}"
}

# Function to show instructions for requesting an account ID and license key
show_request_instructions() {
  echo -e "${GREEN}To request an ElastiFlow account ID and trial license key, visit:${NC}"
  echo -e "${GREEN}https://elastiflow.com/get-started${NC}"
  echo -e "${GREEN}******************************${NC}"
}

# Function to show instructions for obtaining a MaxMind license key
show_maxmind_instructions() {
  echo -e "${GREEN}Create a MaxMind account if you do not have one by going here:${NC}"
  echo -e "${GREEN}https://www.maxmind.com/en/geolite2/signup${NC}"
  echo -e "${GREEN}Obtain your license key by logging in to your maxmind.com account and clicking on “My Account”.${NC}"
  echo -e "${GREEN}******************************${NC}"
}

# Main script execution
show_intro

while true; do
  read -p "Do you want to restore flowcoll.conf to its original state? (yes/y or no/n): " restore
  case $restore in
    yes|y)
      restore="yes"
      break
      ;;
    no|n)
      restore="no"
      break
      ;;
    *)
      echo "Invalid input. Please enter yes/y or no/n."
      ;;
  esac
done

if [ "$restore" = "yes" ]; then
  restore_original
else
  # Show request instructions
  show_request_instructions
  
  # Show MaxMind instructions
  show_maxmind_instructions
  
  # Run the trial configuration function
  configure_trial

  # Run the MaxMind configuration function
  configure_maxmind
fi
