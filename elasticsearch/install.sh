#!/bin/bash

########################################################
# If you do not have an ElastiFlow Account ID and ElastiFlow Flow License Key, 
# please go here: https://elastiflow.com/get-started
# Paste these values on the corresponding line, between the quotes
elastiflow_account_id=""
elastiflow_flow_license_key=""
########################################################

elastiflow_version="7.0.0"
elasticsearch_version="8.14.0"
kibana_version="8.14.0"
flowcoll_config_path="/etc/elastiflow/flowcoll.yml"
elastic_username="elastic"
elastic_password2="elastic"
########################################################

#leave blank
osversion=""

STRINGS_TO_REPLACE=(
"EF_LICENSE_ACCEPTED" "EF_LICENSE_ACCEPTED: \"true\""
"EF_ACCOUNT_ID" "EF_ACCOUNT_ID: \"${elastiflow_account_id}\""
"EF_FLOW_LICENSE_KEY" "EF_FLOW_LICENSE_KEY: \"${elastiflow_flow_license_key}\""
"EF_OUTPUT_ELASTICSEARCH_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ENABLE: \"true\""
"EF_OUTPUT_ELASTICSEARCH_ADDRESSES" "EF_OUTPUT_ELASTICSEARCH_ADDRESSES: \"127.0.0.1:9200\""
"EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE: \"true\""
"EF_OUTPUT_ELASTICSEARCH_PASSWORD" "EF_OUTPUT_ELASTICSEARCH_PASSWORD: \"${elastic_password2}\""
"EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE" "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE: \"true\""
"EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION" "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION: \"true\""
"EF_FLOW_SERVER_UDP_IP" "EF_FLOW_SERVER_UDP_IP: \"0.0.0.0\""
"EF_FLOW_SERVER_UDP_PORT" "EF_FLOW_SERVER_UDP_PORT: \"2055,4739,6343,9995\""
"EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE" "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE: \"33554432\""
"EF_PROCESSOR_DECODE_IPFIX_ENABLE" "EF_PROCESSOR_DECODE_IPFIX_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_MAX_RECORDS_PER_PACKET" "EF_PROCESSOR_DECODE_MAX_RECORDS_PER_PACKET: \"64\""
"EF_PROCESSOR_DECODE_NETFLOW1_ENABLE" "EF_PROCESSOR_DECODE_NETFLOW1_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_NETFLOW5_ENABLE" "EF_PROCESSOR_DECODE_NETFLOW5_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_NETFLOW6_ENABLE" "EF_PROCESSOR_DECODE_NETFLOW6_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_NETFLOW7_ENABLE" "EF_PROCESSOR_DECODE_NETFLOW7_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_NETFLOW9_ENABLE" "EF_PROCESSOR_DECODE_NETFLOW9_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_SFLOW5_ENABLE" "EF_PROCESSOR_DECODE_SFLOW5_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_SFLOW_COUNTERS_ENABLE" "EF_PROCESSOR_DECODE_SFLOW_COUNTERS_ENABLE: \"true\""
"EF_PROCESSOR_DECODE_SFLOW_FLOWS_ENABLE" "EF_PROCESSOR_DECODE_SFLOW_FLOWS_ENABLE: \"true\""
"EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_DNS_ENABLE: \"true\""
"EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_ENABLE" "EF_PROCESSOR_ENRICH_IPADDR_NETINTEL_ENABLE: \"true\""
)

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

backup_and_create_issue_text() {
  # Backup the existing /etc/issue file
  sudo cp /etc/issue /etc/issue.bak

  # Create the new /etc/issue content
  new_issue_content=$(cat << EOF

@@@@@@@@@@@@@@ @@@@@                                @@@@     @@@@  @@@@@@@@@@@@@@@ @@@@
@@@@@@@@@@@@@  @@@@@                               @@@@@     @@@@  @@@@@@@@@@@@@@  @@@@
@@@@           @@@@@     @@@@@@        @@@@@@    @@@@@@@@@@  @@@@  @@@@@           @@@@     @@@@@@@@   @@@@     @@@@     @@@@
@@@@           @@@@@  @@@@@@@@@@@@  @@@@@@@@@@@@ @@@@@@@@@@        @@@@@           @@@@   @@@@@@@@@@@  @@@@@    @@@@@    @@@@
@@@@@@@@@@     @@@@@ @@@@@@  @@@@@  @@@@@  @@@@@@@@@@@@@@@   @@@@  @@@@@@@@@@@     @@@@  @@@@@@@@@@@@@@ @@@@   @@@@@@   @@@@@
@@@@@@@@@      @@@@@          @@@@@ @@@@@@@@       @@@@@     @@@@  @@@@@@@@@@      @@@@ @@@@@     @@@@@ @@@@   @@@@@@@  @@@@
@@@@@@@@       @@@@@  @@@@@@@@@@@@@ @@@@@@@@@@@@   @@@@@     @@@@  @@@@@@@@@       @@@@ @@@@@      @@@@  @@@@ @@@@ @@@ @@@@@
@@@@           @@@@@ @@@@@@@@@@@@@@    @@@@@@@@@@  @@@@@     @@@@  @@@@@           @@@@ @@@@@     @@@@@  @@@@ @@@  @@@@@@@@
@@@@@@@@@@@@@@ @@@@@ @@@@    @@@@@@@@@@@    @@@@@  @@@@@@    @@@@  @@@@@           @@@@ @@@@@@   @@@@@@   @@@@@@@   @@@@@@@
@@@@@@@@@@@@@@ @@@@@ @@@@@@@@@@@@@@ @@@@@@@@@@@@    @@@@@@@  @@@@  @@@@@           @@@@  @@@@@@@@@@@@@    @@@@@@    @@@@@@
@@@@@@@@@@@@@  @@@@@  @@@@@@@ @@@@@  @@@@@@@@@@      @@@@@@  @@@@  @@@@@           @@@@    @@@@@@@@@       @@@@@     @@@@@

=======================================

Welcome to ElastiFlow Virtual Appliance

=======================================

Log in and type sudo ./configure to get started.

Setup Instructions:  https://sites.google.com/elastiflow.com/elastiflow
Documentation:       https://docs.elastiflow.com
Community:           https://forum.elastiflow.com/
Slack:               https://elastiflowcommunity.slack.com
 
 
 
 
 
EOF
  )

  # Write the new content to /etc/issue
  echo "$new_issue_content" | sudo tee /etc/issue
}

print_message() {
  local message=$1
  local color=$2
  echo -e "${color}${message}${NC}"
}

comment_and_replace_line() {
  local FILE=$1
  local FIND=$2
  local REPLACE=$3
  FIND_ESCAPED=$(echo "$FIND" | sed 's/[.[\*^$]/\\&/g')
  REPLACE_ESCAPED=$(echo "$REPLACE" | sed 's/[&/\]/\\&/g')

  if grep -Eq "^[#]*$FIND_ESCAPED" "$FILE"; then
    sed -i.bak "/^[#]*$FIND_ESCAPED/c\\$REPLACE" "$FILE"
    print_message "Replaced '$FIND' with '$REPLACE'." "$GREEN"
  else
    if grep -q "^#ElastiFlow PoC Configurator" "$FILE"; then
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added '$REPLACE' under '#ElastiFlow PoC Configurator'." "$GREEN"
    else
      echo -e "\n#ElastiFlow PoC Configurator" | sudo tee -a "$FILE" > /dev/null
      sed -i.bak "/^#ElastiFlow PoC Configurator/a $REPLACE" "$FILE"
      print_message "Added heading and '$REPLACE'." "$GREEN"
    fi
  fi
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
      echo "$ip_address"
      return 0
    fi
  fi
}

download_file() {
  local url=$1
  local target_path=$2
  curl -o "$target_path" "$url"
  if [ $? -eq 0 ]; then
    chmod +x "$target_path"
    echo "Downloaded and made $target_path executable."
  else
    echo "Failed to download $target_path.\n\n"
  fi
}

get_dashboard_url() {
  local kibana_url="http://$ip_address:5601"
  local dashboard_title="$1"
  local encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  local response=$(curl -s -u "$elastic_username:$elastic_password2" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
  local dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  if [ -z "$dashboard_id" ]; then
    echo "Dashboard not found"
  else
    echo "$kibana_url/app/kibana#/dashboard/$dashboard_id"
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
    comment_and_replace_line "$FILE" "${PAIRS[i]}" "${PAIRS[i+1]}"
  done
}

handle_error() {
  local error_msg="$1"
  local line_num="$2"
  echo "Error at line $line_num: $error_msg"
  read -p "Do you wish to continue? (y/n):" user_decision
  if [[ $user_decision != "y" ]]; then
    echo "Exiting..."
    exit 1
  fi
}

replace_text() {
  local file_path="$1"
  local old_text="$2"
  local new_text="$3"
  local line_num="$4"
  sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}

check_for_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
  fi
}

check_compatibility() {
  . /etc/os-release
  ID_LOWER=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
  if [[ "$ID_LOWER" != "ubuntu" ]]; then
    echo "This script only supports Ubuntu" 1>&2
    exit 1
  fi
  osversion="ubuntu"
}

sleep_message() {
  local message=$1
  local duration=$2
  printf "\n\n\n*********%s*********\n\n" "$message"
  sleep "$duration"
}

print_startup_message() {
  printf "*********\n"
  printf "*********\n"
  printf "*********Setting up ElastiFlow environment...*********\n"
  printf "*********\n"
  printf "*********\n"
}

install_prerequisites() {
  printf "\n\n\n*********Installing prereqs...\n\n"
  apt-get -qq update && apt-get -qq install jq net-tools git bc gpg default-jre curl wget unzip apt-transport-https isc-dhcp-client libpcap-dev
}

tune_system() {
  printf "\n\n\n*********System tuning starting...\n\n"
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
  sed -i '/net.core.netdev_max_backlog=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_default=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.core.rmem_max=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_rmem_min=/s/^/#/' /etc/sysctl.conf
  sed -i '/net.ipv4.udp_mem=/s/^/#/' /etc/sysctl.conf
  sed -i '/vm.max_map_count=/s/^/#/' /etc/sysctl.conf
  echo "$kernel_tuning" >> /etc/sysctl.conf
  sysctl -p
  echo "Kernel parameters updated in /etc/sysctl.conf with previous configurations commented out."
  mkdir /etc/systemd/system/elasticsearch.service.d && \
  echo -e "[Service]\nLimitNOFILE=131072\nLimitNPROC=8192\nLimitMEMLOCK=infinity\nLimitFSIZE=infinity\nLimitAS=infinity" | \
  tee /etc/systemd/system/elasticsearch.service.d/elasticsearch.conf > /dev/null
  echo "System limits set"
  printf "\n\n\n*********System tuning done...\n\n"
}

install_elasticsearch() {
  printf "\n\n\n*********Installing ElasticSearch...\n\n"
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list || handle_error "Failed to add Elasticsearch repository." "${LINENO}"
  elastic_install_log=$(apt-get -q update && apt-get -q install elasticsearch=$elasticsearch_version | stdbuf -oL tee /dev/tty) || handle_error "Failed to install Elasticsearch." "${LINENO}"
  elastic_password=$(echo "$elastic_install_log" | awk -F' : ' '/The generated password for the elastic built-in superuser/{print $2}') 
  elastic_password=$(echo -n "$elastic_password" | tr -cd '[:print:]')
  printf "\n\n\nElastic password: $elastic_password\n\n"
}

configure_jvm_memory() {
  printf "\n\n\n*********Configuring JVM memory usage...\n\n"
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
  echo "Elasticsearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx."
}

start_elasticsearch() {
  printf "\n\n\n*********Enabling and starting ElasticSearch service...\n\n"
  systemctl daemon-reload && systemctl enable elasticsearch.service && systemctl start elasticsearch.service
  sleep_message "Giving ElasticSearch service time to stabilize" 10
  if systemctl is-active --quiet elasticsearch.service; then
    printf "\n\n\n*********\e[32mElasticsearch service is up\e[0m\n\n"
  else
    echo "Elasticsearch is not running."
  fi
  printf "\n\n\n*********Checking if Elastic server is up...\n\n"
  curl_result=$(curl -s -k -u $elastic_username:$elastic_password https://localhost:9200)
  search_text='cluster_name" : "elasticsearch'
  if echo "$curl_result" | grep -q "$search_text"; then
      echo -e "\e[32mElastic is up!\e[0m\n\n"
  else
    echo -e "Something's wrong with Elastic...\n\n"
  fi
}

install_kibana() {
  printf "\n\n\n*********Downloading and installing Kibana...\n\n"
  apt-get -q update && apt-get -q install kibana=$kibana_version
}

configure_kibana() {
  printf "\n\n\n*********Generating Kibana saved objects encryption key...\n\n"
  output=$(/usr/share/kibana/bin/kibana-encryption-keys generate -q)
  key_line=$(echo "$output" | grep '^xpack.encryptedSavedObjects.encryptionKey')
  if [[ -n "$key_line" ]]; then
      echo "$key_line" | sudo tee -a /etc/kibana/kibana.yml > /dev/null
  else
      echo "No encryption key line found."
  fi
  printf "\n\n\n*********Generating Kibana enrollment token...\n\n"
  kibana_token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
  printf "\n\n\nKibana enrollment token is:\n\n$kibana_token\n\n"
  printf "\n\n\n*********Enrolling Kibana with Elastic...\n\n"
  /usr/share/kibana/bin/kibana-setup --enrollment-token $kibana_token
  printf "\n\n\n*********Enabling and starting Kibana service...\n\n"
  systemctl daemon-reload && systemctl enable kibana.service && systemctl start kibana.service
  sleep_message "Giving Kibana service time to stabilize" 10
  printf "\n\n\n*********Configuring Kibana - set 0.0.0.0 as server.host\n\n"
  replace_text "/etc/kibana/kibana.yml" "#server.host: \"localhost\"" "server.host: \"0.0.0.0\"" "${LINENO}"
  printf "\n\n\n*********Configuring Kibana - set elasticsearch.hosts to localhost instead of DHCP IP...\n\n"
  replace_text "/etc/kibana/kibana.yml" "elasticsearch.hosts: \['https:\/\/[^']*'\]" "elasticsearch.hosts: \['https:\/\/localhost:9200'\]" "${LINENO}"
  replace_text "/etc/kibana/kibana.yml" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"
  sleep_message "Giving Kibana service time to stabilize" 10
  systemctl daemon-reload && systemctl enable kibana.service && systemctl start kibana.service
}

change_elasticsearch_password() {
  printf "\n\n\n*********Changing Elastic password to \"elastic\"...\n\n"
  curl -k -X POST -u "$elastic_username:$elastic_password" "https://localhost:9200/_security/user/elastic/_password" -H 'Content-Type: application/json' -d"
  {
    \"password\": \"$elastic_password2\"
  }"
  elastic_password=$elastic_password2
}

install_elastiflow() {
  printf "\n\n\n*********Downloading and installing ElastiFlow Flow Collector...\n\n" 
  wget -O flow-collector_"$elastiflow_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$elastiflow_version"_linux_amd64.deb
  apt-get -q install ./flow-collector_"$elastiflow_version"_linux_amd64.deb
  change_elasticsearch_password
  printf "\n\n\n*********Configuring ElastiFlow Flow Collector...\n\n" 
  find_and_replace "$flowcoll_config_path" "${STRINGS_TO_REPLACE[@]}"
  replace_text "/etc/systemd/system/flowcoll.service" "TimeoutStopSec=infinity" "TimeoutStopSec=60" "N/A"
  printf "\n\n\n*********Enabling and starting ElastiFlow service...\n\n"
  systemctl daemon-reload && systemctl enable flowcoll.service && systemctl start flowcoll.service
  sleep_message "Giving ElastiFlow service time to stabilize" 10
}

install_dashboards() {
  printf "\n\n\n*********Downloading and installing ElastiFlow flow dashboards\n\n"
  git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/
  response=$(curl --connect-timeout 10 -X POST -u $elastic_username:$elastic_password "localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" --form file=@/etc/elastiflow_for_elasticsearch/kibana/flow/kibana-8.2.x-flow-ecs.ndjson -H 'kbn-xsrf: true')
  dashboards_success=$(echo "$response" | jq -r '.success')
  if [ "$dashboards_success" == "true" ]; then
      printf "Flow dashboards installed successfully.\n\n"
  else
      printf "Flow dashboards not installed successfully\n\n"
  fi
}

check_service_status() {
  local SERVICE_NAME=$1
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "\e[32m$SERVICE_NAME is up ✓\e[0m"
  else
    echo -e "\e[31m$SERVICE_NAME is not up X\e[0m"
  fi
}

check_all_services() {
  SERVICES=("elasticsearch.service" "kibana.service" "flowcoll.service")
  for SERVICE_NAME in "${SERVICES[@]}"; do
      check_service_status "$SERVICE_NAME"
  done
}

check_dashboards_status() {
  if [ "$dashboards_success" == "true" ]; then
       echo -e "\e[32mDashboards are installed ✓\e[0m"
  else
       echo -e "\e[31mDashboards are not installed X\e[0m"
  fi
}

display_versions() {
  version=$(/usr/share/elastiflow/bin/flowcoll -version)
  printf "Installed ElastiFlow version: $version\n"
  version=$(/usr/share/kibana/bin/kibana --version --allow-root | jq -r '.config.serviceVersion.value' 2>/dev/null)
  printf "Installed Kibana version: $version\n"
  version=$(/usr/share/elasticsearch/bin/elasticsearch --version | grep -oP 'Version: \K[\d.]+')
  printf "Installed Elasticsearch version: $version\n" 
  version=$(java -version 2>&1)
  printf "Installed Java version: $version\n"
  version=$(lsb_release -d | awk -F'\t' '{print $2}')
  printf "Operating System: $version\n"
}

display_dashboard_url() {
  dashboard_url=$(get_dashboard_url "ElastiFlow (flow): Overview")
  printf "*********************************************\n"
  printf "\033[32m\n\nGo to %s (%s / %s)\n\n\033[0m" "$dashboard_url" "$elastic_username" "$elastic_password2"
  printf "For further configuration options, run sudo ./configure\n\n"
  printf "*********************************************\n"
}

remove_update_service(){
  printf "\n\n\n*********Removing Ubuntu update service...\n\n"
  apt remove -y unattended-upgrades
}

append_to_bashrc() {
    local text="$1"
    # Append the text to .bashrc
    echo "$text" >> /home/user/.bashrc
    echo "The script has been added to .bashrc."

    # Reload the .bashrc file
    . /home/user/.bashrc
    echo ".bashrc has been reloaded."
}

main() {
  check_for_root
  check_compatibility
  print_startup_message
  ip_address=$(get_host_ip)
  remove_update_service
  install_prerequisites
  tune_system
  sleep_message "Giving dpkg time to clean up" 10
  install_elasticsearch
  configure_jvm_memory
  start_elasticsearch
  sleep_message "Giving dpkg time to clean up" 10
  install_kibana
  configure_kibana
  install_elastiflow
  install_dashboards
  check_all_services
  check_dashboards_status
  download_file "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/configure/configure" "/home/user/configure"
  download_file "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/support_pack/elastiflow_elasticsearch_opensearch_support_pack" "/home/user/support"
  display_versions
  display_dashboard_url

  backup_and_create_issue_text
  ####set configure script to run on first logon

  history -c
  
  
#  script_text='
#export ELASTIFLOW_FIRST_BOOT=1
#  '
#  append_to_bashrc "$script_text"
#  
#  script_text='
#  if [ "$ELASTIFLOW_FIRST_BOOT" -eq 1 ]; then
#      sudo ./configure
#  fi
#  '
#  append_to_bashrc "$script_text"
}

main
