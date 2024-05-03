#!/bin/bash

# Replace text in a file with error handling
replace_text() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local line_num="$4"
    sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}


printf "\n\n\n*********Removing Ubuntu update service...\n\n"
#systemctl stop unattended-upgrades.service 
apt remove -y unattended-upgrades

printf "\n\n\n*********Installing jq and git...\n\n"
apt-get -qq update && apt-get -qq install jq net-tools git

printf "\n\n\n*********Stopping Ubuntu pop-up \"Daemons using outdated libraries\" when using apt to install or update packages...\n\n"
needrestart_conf_path="/etc/needrestart/needrestart.conf"
replace_text "$needrestart_conf_path" "#\$nrconf{restart} = 'i';" "\$nrconf{restart} = 'a';" "${LINENO}"

printf "installing components\n\n"
sudo apt-get -y -qq update && apt-get -qq install software-properties-common
sudo add-apt-repository --yes ppa:oisf/suricata-stable
sudo apt-get -y -qq update
sudo apt-get -y -qq install suricata jq
#sudo suricata --build-info
#sudo systemctl status suricata

printf "obtaining name of eth interface\n\n"
interface=$(ifconfig -a | awk '/^en/ {gsub(":", "", $1); print $1}')

# Replace the first occurrence of "- interface: eth0" found after "af-packet"
replace_text "/etc/suricata/suricata.yaml" "interface: eth0" "interface: $interface" "${LINENO}"


printf "Updating rules\n\n"
sudo suricata-update

printf "Restarting service and verifying\n\n"
sudo systemctl restart suricata

printf "Checking if the service is active\n\n"
service_name="suricata"
if systemctl is-active --quiet "$service_name"; then
    echo -e "\e[32mThe $service_name service is active (running).\e[0m"
else
    echo "The $service_name service is not active."
fi

sleep 30

printf "\n\nExecuting test threat and monitoring for detection...\n\n"
url="http://testmynids.org/uid/index.html"
log_file="/var/log/suricata/fast.log"
search_text="GPL ATTACK_RESPONSE id check"

# Run the curl command
#curl -s "$url" -o /dev/null

sleep 5

# Check if the search text is found in the log file
if grep -qE "$search_text" "$log_file"; then
    echo -e "\e[32mTest threat detected\e[0m"
    echo -e "\e[32m\"$search_text\" found in $log_file\e[0m"
else
    # If not found, print a message
    echo "No threat detected in the log file. Something's not right\n\n"
fi

printf "\n\nSuricata installation complete. Monitoring interface $interface.\n\n"
