#!/bin/bash

osversion=""

########################################################

# If you do not have an ElastiFlow Account ID and ElastiFlow Flow License Key, 
# please go here: https://elastiflow.com/get-started
# Paste these values on the corresponding line, between the quotes

elastiflow_account_id=""
elastiflow_flow_license_key=""

elastiflow_version="6.4.2"
flowcoll_config_path="/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
########################################################

# Function to handle errors
handle_error() {
    local error_msg="$1"
    local line_num="$2"
    local user_decision

    echo "Error at line $line_num: $error_msg"
    echo "Do you wish to continue? (y/n):"
    read user_decision

    if [[ $user_decision == "y" ]]; then
        echo "Continuing execution..."
    elif [[ $user_decision == "n" ]]; then
        echo "Exiting..."
        exit 1
    else
        echo "Invalid input. Exiting..."
        exit 1
    fi
}
# Replace text in a file with error handling
replace_text() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local line_num="$4"
    sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}


check_for_root(){
# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi
}

check_compatibility(){
# Parse /etc/os-release to get OS information
. /etc/os-release

# Convert ID to lowercase
ID_LOWER=$(echo "$ID" | tr '[:upper:]' '[:lower:]')

# Check if the OS is Ubuntu or Debian
if [[ "$ID_LOWER" == "ubuntu" ]]; then
    echo "Found Ubuntu"
    osversion="ubuntu"
elif [[ "$ID_LOWER" == "debian" ]]; then
    echo "Found Debian"
    osversion="debian"
else
    echo "This script only supports Ubuntu or Debian" 1>&2
    exit 1
fi
}


net_config() {
    # Check if the OS is Ubuntu or Debian
    if [[ "$osversion" == "ubuntu" ]]; then
        # Replace the content with the new configuration
        FILE_PATH="/etc/netplan/00-installer-config.yaml"
        cat <<EOL > "$FILE_PATH"
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      dhcp-timeout: 60
      dhcp-fallback:
        addresses:
          - 192.168.55.100/24
        gateway4: 192.168.55.1
        nameservers:
          addresses: [8.8.8.8, 8.8.4.4]
EOL
    elif [[ "$osversion" == "debian" ]]; then
        echo "hey there"
    else
        echo "This script requires Ubuntu or Debian" 1>&2
        exit 1
    fi
}


check_compatibility

printf "*********\n"
printf "*********\n"
printf "*********Setting up ElastiFlow environment...*********\n"
printf "*********\n"
printf "*********\n"

printf "\n\n\n*********Removing Ubuntu update service...\n\n"
#systemctl stop unattended-upgrades.service 
apt remove -y unattended-upgrades

printf "\n\n\n*********Installing prereqs...\n\n"
apt-get -qq update && apt-get -qq install jq net-tools git bc gpg default-jre curl wget unzip apt-transport-https

printf "\n\n\n*********Stopping Ubuntu pop-up "Daemons using outdated libraries" when using apt to install or update packages...\n\n"
needrestart_conf_path="/etc/needrestart/needrestart.conf"
if [ -f "$needrestart_conf_path" ]; then
    echo "$needrestart_conf_path exists."
    replace_text "$needrestart_conf_path" "#\$nrconf{restart} = 'i';" "\$nrconf{restart} = 'a';" "${LINENO}"
else
    printf "\n\n$needrestart_conf_path does not exist."
fi

printf "\n\n\n*********System tuning starting...\n\n"
#!/bin/bash

# Define kernel parameters as a block of text
kernel_tuning=$(cat <<EOF
#####ElastiFlow tuning parameters######
net.core.netdev_max_backlog=4096
net.core.rmem_default=262144
net.core.rmem_max=67108864
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_mem=2097152 4194304 8388608
vm.max_map_count=262144
#######################################
EOF
)

# This comments out existing lines containing these parameters in /etc/sysctl.conf
sed -i '/net.core.netdev_max_backlog=/s/^/#/' /etc/sysctl.conf
sed -i '/net.core.rmem_default=/s/^/#/' /etc/sysctl.conf
sed -i '/net.core.rmem_max=/s/^/#/' /etc/sysctl.conf
sed -i '/net.ipv4.udp_rmem_min=/s/^/#/' /etc/sysctl.conf
sed -i '/net.ipv4.udp_mem=/s/^/#/' /etc/sysctl.conf
sed -i '/vm.max_map_count=/s/^/#/' /etc/sysctl.conf

# Append the new kernel parameters block to /etc/sysctl.conf
echo "$kernel_tuning" >> /etc/sysctl.conf

# Reload the sysctl settings
sysctl -p

echo "Kernel parameters updated in /etc/sysctl.conf with previous configurations commented out."


#Increase System Limits (all ES nodes)
#Increased system limits should be specified in a systemd attributes file for the elasticsearch service.
mkdir /etc/systemd/system/elasticsearch.service.d && \
echo -e "[Service]\nLimitNOFILE=131072\nLimitNPROC=8192\nLimitMEMLOCK=infinity\nLimitFSIZE=infinity\nLimitAS=infinity" | \
tee /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf > /dev/null
echo "System limits set"
printf "\n\n\n*********System tuning done...\n\n"


printf "\n\n\n*********Sleeping 20 seconds to give dpkg time to clean up...\n\n"
sleep 20s

printf "\n\n\n*********Installing ElasticSearch...\n\n"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
elastic_install_log=$(apt-get -qq update && apt-get -qq install elasticsearch | stdbuf -oL tee /dev/tty) || handle_error "Failed to install Elasticsearch." "${LINENO}"
elastic_password=$(echo "$elastic_install_log" | awk -F' : ' '/The generated password for the elastic built-in superuser/{print $2}') 
elastic_password=$(echo -n "$elastic_password" | tr -cd '[:print:]')
printf "\n\n\n*********Elastic password is $elastic_password\n\n"

printf "\n\n\n*********Configuring JVM memory usage...\n\n"
# Get the total installed memory from /proc/meminfo in kB
total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert the memory from kB to GB and divide by 3 to get 1/3, using bc for floating point support
one_third_mem_gb=$(echo "$total_mem_kb / 1024 / 1024 / 3" | bc -l)

# Use printf to round the floating point number to an integer
rounded_mem_gb=$(printf "%.0f" $one_third_mem_gb)

# Ensure the value does not exceed 31GB
if [ $rounded_mem_gb -gt 31 ]; then
    jvm_mem_gb=31
else
    jvm_mem_gb=$rounded_mem_gb
fi

# Prepare the JVM options string with the calculated memory size
jvm_options="-Xms${jvm_mem_gb}g\n-Xmx${jvm_mem_gb}g"

# Echo the options and use tee to write to the file
echo -e $jvm_options | tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null

echo "Elasticsearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx."

printf "\n\n\n*********Enabling and starting ElasticSearch service...\n\n"
systemctl daemon-reload && systemctl enable elasticsearch.service && systemctl start elasticsearch.service

printf "\n\n\n*********Sleeping 20 seconds to give service time to stabilize...\n\n"
sleep 20s

if systemctl is-active --quiet elasticsearch.service; then
  printf "\n\n\n*********\e[32mElasticsearch service is up\e[0m\n\n"
else
  echo "Elasticsearch is not running."
fi

printf "\n\n\n*********Checking if Elastic server is up...\n\n"
#curl_result=$(curl -s --cacert /etc/elasticsearch/certs/http_ca.crt -u elastic:$elastic_password https://localhost:9200 | tee /dev/tty) 
curl_result=$(curl -s -k -u elastic:$elastic_password https://localhost:9200 | tee /dev/tty) 

search_text='cluster_name" : "elasticsearch'
if echo "$curl_result" | grep -q "$search_text"; then
    echo -e "\e[32mElastic is up!\e[0m\n\n"
else
  echo -e "Something's wrong with Elastic...\n\n"
fi

printf "\n\n\n*********Generating Kibana enrollment token...\n\n"
kibana_token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
printf "\n\n\nKibana enrollment token is:\n\n $kibana_token\n\n"

printf "\n\n\n*********Sleeping 20 seconds to give dpkg time to clean up...\n\n"
sleep 20s

printf "\n\n\n*********Downloading and installing Kibana...\n\n"
apt-get -qq update && apt-get -qq install kibana

printf "\n\n\n*********Configuring Kibana - set 0.0.0.0 as server.host\n\n"
## The default is 'localhost', which usually means remote machines will not be able to connect.
kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" "#server.host: \"localhost\"" "server.host: \"0.0.0.0\"" "${LINENO}"

printf "\n\n\n*********Enrolling Kibana with Elastic...\n\n"
/usr/share/kibana/bin/kibana-setup --enrollment-token $kibana_token

printf "\n\n\n*********Configuring Kibana - set elasticsearch.hosts to localhost instead of DHCP IP...\n\n"
kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" "elasticsearch.hosts: \['https:\/\/[^']*'\]" "elasticsearch.hosts: \['https:\/\/localhost:9200'\]" "${LINENO}"
replace_text "$kibana_config_path" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"

printf "\n\n\n*********Generating Kibana saved objects encryption key...\n\n"
# Run the command to generate encryption keys quietly
output=$(/usr/share/kibana/bin/kibana-encryption-keys generate -q)

# Extract the line that starts with 'xpack.reporting.encryptionKey'
key_line=$(echo "$output" | grep '^xpack.encryptedSavedObjects.encryptionKey')

# Check if the key line was found
if [[ -n "$key_line" ]]; then
    # Append the key line to /etc/kibana/kibana.yml
    echo "$key_line" | sudo tee -a /etc/kibana/kibana.yml > /dev/null
else
    echo "No encryption key line found."
fi

printf "\n\n\n*********Enabling and starting Kibana service...\n\n"
systemctl daemon-reload && systemctl enable kibana.service && systemctl start kibana.service

printf "\n\n\n*********Sleeping 20 seconds to give service time to stabilize...\n\n"
sleep 20s

printf "\n\n\n*********Downloading and installing ElastiFlow Flow Collector...\n\n" 
#Install Elastiflow flow collector
wget -O flow-collector_"$elastiflow_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$elastiflow_version"_linux_amd64.deb
apt-get -qq install libpcap-dev
apt-get -qq install ./flow-collector_"$elastiflow_version"_linux_amd64.deb

printf "\n\n\n*********Changing Elastic password to \"elastic\"...\n\n"
curl -k -X POST -u elastic:$elastic_password "https://localhost:9200/_security/user/elastic/_password" -H 'Content-Type: application/json' -d'
{
  "password" : "elastic"
}'

elastic_password="elastic"

printf "\n\n\n*********Configuring ElastiFlow Flow Collector...\n\n" 

replace_text "$flowcoll_config_path" 'Environment="EF_LICENSE_ACCEPTED=false"' 'Environment="EF_LICENSE_ACCEPTED=true"' "${LINENO}"
replace_text "$flowcoll_config_path" '#Environment="EF_ACCOUNT_ID="' "Environment=\"EF_ACCOUNT_ID=$elastiflow_account_id\"" "${LINENO}"
replace_text "$flowcoll_config_path" '#Environment="EF_FLOW_LICENSE_KEY="' "Environment=\"EF_FLOW_LICENSE_KEY=$elastiflow_flow_license_key\"" "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_ELASTICSEARCH_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_ELASTICSEARCH_PASSWORD=changeme"' "Environment=\"EF_OUTPUT_ELASTICSEARCH_PASSWORD=$elastic_password\"" "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION=true"' "${LINENO}"

#Configure flowcoll service to stop after 60 seconds when asked to terminate so this does not hold up the system forever on shutdown.
replace_text "/etc/systemd/system/flowcoll.service" "TimeoutStopSec=infinity" "TimeoutStopSec=60" "N/A"

printf "\n\n\n*********Enabling and starting ElastiFlow service...\n\n"
#Start Elastiflow flow collector
systemctl daemon-reload && systemctl enable flowcoll.service && systemctl start flowcoll.service

#Install Elastiflow SNMP collector
#wget https://elastiflow-releases.s3.us-east-2.amazonaws.com/snmp-collector/snmp-collector_6.4.2_linux_amd64.deb
#apt install ./snmp-collector_6.4.2_linux_amd64.deb
#systemctl daemon-reload && systemctl enable snmpcoll.service && systemctl start snmp.service

printf "\n\n\n*********Sleeping 20 seconds to give service time to stabilize...\n\n"
sleep 20s

printf "\n\n\n*********Downloading and installing ElastiFlow flow dashboards\n\n"
git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/
response=$(curl --connect-timeout 10 -X POST -u elastic:$elastic_password "localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" --form file=@/etc/elastiflow_for_elasticsearch/kibana/flow/kibana-8.2.x-flow-ecs.ndjson -H 'kbn-xsrf: true')

dashboards_success=$(echo "$response" | jq -r '.success')

if [ "$dashboards_success" == "true" ]; then
    printf "Flow dashboards installed successfully.\n\n"
else
    printf "Flow dashboards not installed successfully\n\n"
fi

#printf "\n\n\n*********Clean up - Shutting down machine\n\n"
#shutdown -h now

#printf "\n\n\n*********Elastic trial license started\n\n"
#curl -X POST -k 'https://localhost:9200/_license/start_trial?acknowledge=true' -u elastic:$elastic_password

# Loop through each service in the array

SERVICES=("elasticsearch.service" "kibana.service" "flowcoll.service") # Replace these with actual service names
for SERVICE_NAME in "${SERVICES[@]}"; do
    # Check if the service is active
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        # If the service is up, print the message in green
        echo -e "\e[32m$SERVICE_NAME is up ✓\e[0m"
    else
        # If the service is not up, print the message in red
        echo -e "\e[31m$SERVICE_NAME is not up X\e[0m"
    fi
done

if [ "$dashboards_success" == "true" ]; then
     echo -e "\e[32mDashboards are installed ✓\e[0m"
else
     echo -e "\e[31mDashboards are not installed X\e[0m"
fi

# Get the first network interface starting with enp
INTERFACE=$(ip -o link show | grep -o 'enp[^:]*' | head -n 1)

if [ -z "$INTERFACE" ]; then
    echo "No interface starting with 'enp' found."
else
    # Get the IP address of the interface
    IP_ADDRESS=$(ip -o -4 addr show $INTERFACE | awk '{print $4}' | cut -d/ -f1)

    if [ -z "$IP_ADDRESS" ]; then
        echo "No IP address found for interface $INTERFACE."
    fi
fi

#Get installed versions
version=$(/usr/share/elasticsearch/bin/elasticsearch --version | grep -oP 'Version: \K[\d.]+')
printf "\n\nInstalled Elasticsearch version: $version\n" 

version=$(/usr/share/kibana/bin/kibana --version --allow-root | jq -r '.config.serviceVersion.value' 2>/dev/null)
printf "Installed Kibana version: $version\n" 

version=$(/usr/share/elastiflow/bin/flowcoll -version)
printf "Installed ElastiFlow version: $version\n"

version=$(lsb_release -d | awk -F'\t' '{print $2}')
printf "Operating System: $version\n\n"

printf "\e[5;37m\n\nGo to http://$IP_ADDRESS:5601/app/dashboards (elastic / elastic)\n\n\e[0m"

printf "Open ElastiFlow dashboard: “ElastiFlow (flow): Overview\"\n\n"

#configure network for dhcp wiht fallback to static
net_config

printf "\n\nDone\n"

