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

apt-get -y install pmacct

printf "obtaining name of eth interface\n\n"
interface=$(ifconfig -a | awk '/^en/ {gsub(":", "", $1); print $1}')

printf "writing configuration file...\n\n"
filepath=/etc/pmacct/pmacctd.conf
config_content="
daemonize: false
pcap_interface: $interface
aggregate: src_mac, dst_mac, src_host, dst_host, src_port, dst_port, proto, tos
plugins: nfprobe, print
nfprobe_receiver: localhost:9995
"
# Specify the file path
file_path="/etc/pmacct/pmacctd.conf"

# Write the configuration to the file
echo "$config_content" > "$file_path"

# Print a message indicating that the operation is complete
echo "Configuration has been written to $file_path"

printf "running pcacctd netflow generator"
pmacctd -f $file_path
