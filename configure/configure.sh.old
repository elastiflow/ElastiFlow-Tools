#!/bin/bash

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

elastiflow_version="6.4.4"


# Function to check if flowcoll.service exists
check_service_exists() {
  if ! systemctl list-unit-files | grep -q "flowcoll.service"; then
    echo -e "${RED}flowcoll.service does not exist. Exiting.${NC}"
    exit 1
  fi
}

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
  TIMESTAMP=$(date +%Y%m%d%H%M%S)

  # Backup the existing configuration file if it exists
  if [ -f $FILE_PATH ]; then
    sudo cp -f $FILE_PATH ${FILE_PATH}.bak.$TIMESTAMP
    echo -e "${GREEN}Backed up the existing $FILE_PATH to ${FILE_PATH}.bak.$TIMESTAMP.${NC}"
  fi

  # Restore the latest backup
  LATEST_BACKUP=$(ls -t ${FILE_PATH}.bak.* 2>/dev/null | head -1)
  if [ -f $LATEST_BACKUP ]; then
    sudo cp -f $LATEST_BACKUP $FILE_PATH
    echo -e "${GREEN}Restored $FILE_PATH from the latest backup: $LATEST_BACKUP.${NC}"
  else
    # Create a default flowcoll.conf if no backup exists
    echo "[Service]" | sudo tee $FILE_PATH > /dev/null
    echo "Environment=\"EF_LICENSE_ACCEPTED=true\"" | sudo tee -a $FILE_PATH > /dev/null
    echo "Environment=\"EF_ACCOUNT_ID=your_account_id\"" | sudo tee -a $FILE_PATH > /dev/null
    echo "Environment=\"EF_FLOW_LICENSE_KEY=your_license_key\"" | sudo tee -a $FILE_PATH > /dev/null
    echo -e "${GREEN}No backup found. Created a default $FILE_PATH.${NC}"
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
  wget -O flow-collector_"$elastiflow_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$elastiflow_version"_linux_amd64.deb
  dpkg-deb -xv flow-collector.deb /tmp/elastiflow > /dev/null
  sudo mkdir -p /etc/systemd/system/flowcoll.service.d/
  sudo cp /tmp/elastiflow/etc/systemd/system/flowcoll.service.d/flowcoll.conf /etc/systemd/system/flowcoll.service.d/
  sudo rm -rf /tmp/elastiflow
  echo -e "${GREEN}Default flowcoll.conf downloaded and copied.${NC}"
}

# Function to validate IP address in CIDR format
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

# Function to validate IP address format
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

# Function to configure static IP address using netplan
configure_static_ip() {
  # List available network interfaces excluding Docker interfaces
  echo "Available network interfaces:"
  interfaces=($(ip link show | awk -F: '$1 ~ /^[0-9]+$/ && $2 !~ /^ lo|^ docker/ {print $2}' | sed 's/ //g'))
  for i in "${!interfaces[@]}"; do
    echo "$((i+1)). ${interfaces[$i]}"
  done
  
  # Prompt for network interface
  while true; do
    read -p "Enter the number corresponding to the interface you want to configure: " interface_number
    if [[ $interface_number -ge 1 && $interface_number -le ${#interfaces[@]} ]]; then
      interface=${interfaces[$((interface_number-1))]}
      break
    else
      echo -e "${RED}Invalid selection. Please choose a valid interface number.${NC}"
    fi
  done
  
  # Set the interface to up status
  sudo ip link set $interface up

  # Prompt for IP address, default gateway, and DNS servers
  while true; do
    read -p "Enter IP address (CIDR format, e.g., 192.168.1.100/24): " ip_address
    if [[ $(validate_cidr $ip_address) -eq 1 ]]; then
      break
    else
      echo -e "${RED}Invalid IP address format. Please enter a valid IP address in CIDR format.${NC}"
    fi
  done

  read -p "Enter default gateway (optional): " default_gateway
  if [[ -n "$default_gateway" && $(validate_ip $default_gateway) -eq 0 ]]; then
    echo -e "${RED}Invalid gateway address format. Please enter a valid IP address.${NC}"
    return
  fi

  read -p "Enter DNS servers (comma separated, optional): " dns_servers
  if [[ -n "$dns_servers" ]]; then
    IFS=',' read -r -a dns_array <<< "$dns_servers"
    for dns in "${dns_array[@]}"; do
      if [[ $(validate_ip $dns) -eq 0 ]]; then
        echo -e "${RED}Invalid DNS server address format. Please enter valid IP addresses.${NC}"
        return
      fi
    done
  fi

  # Confirm configuration
  echo -e "${GREEN}Configuration:${NC}"
  echo "Interface: $interface"
  echo "IP address: $ip_address"
  echo "Default gateway: ${default_gateway:-None}"
  echo "DNS servers: ${dns_servers:-None}"
  read -p "Do you want to apply these settings? (y/n): " confirm
  if [[ $confirm != "y" ]]; then
    echo "Discarding changes."
    return
  fi

  # Find the current netplan configuration file
  netplan_file=$(find /etc/netplan -name "*.yaml" | head -n 1)
  
  # Backup the current netplan configuration file
  sudo cp $netplan_file ${netplan_file}.bak.$(date +%Y%m%d%H%M%S)

  # Update netplan configuration
  sudo tee $netplan_file > /dev/null <<EOL
network:
  version: 2
  ethernets:
    $interface:
      addresses:
        - $ip_address
EOL

  if [ -n "$default_gateway" ]; then
    sudo tee -a $netplan_file > /dev/null <<EOL
      routes:
        - to: default
          via: $default_gateway
EOL
  fi

  if [ -n "$dns_servers" ]; then
    sudo tee -a $netplan_file > /dev/null <<EOL
      nameservers:
        addresses: [$dns_servers]
EOL
  fi

  # Apply netplan configuration
  sudo netplan apply

  echo -e "${GREEN}Static IP address configuration applied successfully.${NC}"
}

# Function to revert network interface changes
revert_network_changes() {
  # List available backups
  echo "Available backups:"
  backups=($(ls /etc/netplan/*.bak.*))
  for i in "${!backups[@]}"; do
    echo "$((i+1)). ${backups[$i]}"
  done
  
  # Prompt for backup to restore
  while true; do
    read -p "Enter the number corresponding to the backup you want to restore: " backup_number
    if [[ $backup_number -ge 1 && $backup_number -le ${#backups[@]} ]]; then
      backup=${backups[$((backup_number-1))]}
      break
    else
      echo -e "${RED}Invalid selection. Please choose a valid backup number.${NC}"
    fi
  done
  
  # Restore the selected backup
  sudo cp $backup /etc/netplan/$(basename $backup | sed 's/.bak.*//')
  sudo netplan apply

  echo -e "${GREEN}Network configuration reverted successfully.${NC}"
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

check_service_exists

while true; do
  show_intro
  echo "Choose an option:"
  echo "1. Configure fully featured trial"
  echo "2. Enable MaxMind enrichment"
  echo "3. Restore flowcoll.conf from latest backup"
  echo "4. Download default flowcoll.conf from deb file"
  echo "5. Configure static IP address"
  echo "6. Revert network interface changes"
  echo "7. Quit"
  read -p "Enter your choice (1-7): " choice
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
      configure_static_ip
      ;;
    6)
      revert_network_changes
      ;;
    7)
      echo "Exiting the script."
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter a number between 1 and 7."
      ;;
  esac
done
