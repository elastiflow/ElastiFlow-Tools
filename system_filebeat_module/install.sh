#!/bin/bash

system_module_config="/etc/filebeat/modules.d/system.yml"

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
curl -sS -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.13.3-amd64.deb
dpkg -i filebeat-8.13.3-amd64.deb

filebeat modules enable system

cp /etc/filebeat/modules.d/system.yml.disabled $system_module_config

replace_text "/path/to/your/file.yaml" "syslog:\n    enabled: false" "syslog:\n    enabled: true"
replace_text "/path/to/your/file.yaml" "auth:\n    enabled: false" "auth:\n    enabled: true"
