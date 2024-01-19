#!/bin/bash

elastiflow_version="6.4.2"

# Function to handle errors
handle_error() {
    local error_msg="$1"
    local line_num="$2"
    echo "Error at line $line_num: $error_msg"
    exit 1
}

# Replace text in a file with error handling
replace_text() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local line_num="$4"
    sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}

printf "*********\n"
printf "*********\n"
printf "*********Setting up ElastiFlow VM...*********\n"
printf "*********\n"
printf "*********\n"

printf "\n\n\n*********Removing Ubuntu update service...\n\n"
#systemctl stop unattended-upgrades.service 
apt remove -y unattended-upgrades

printf "\n\n\n*********Installing jq and git...\n\n"
apt-get -qq update && apt-get -qq install jq net-tools git

printf "\n\n\n*********Stopping Ubuntu pop-up "Daemons using outdated libraries" when using apt to install or update packages...\n\n"
needrestart_conf_path="/etc/needrestart/needrestart.conf"
replace_text "$needrestart_conf_path" "#\$nrconf{restart} = 'i';" "\$nrconf{restart} = 'a';" "${LINENO}"

printf "\n\n\n*********Setting vm.max_map_count...\n\n"
sysctl_file="/etc/sysctl.conf"
max_map_count_setting="vm.max_map_count = 262144"

# Check if the setting exists in sysctl.conf
if grep -q "^$max_map_count_setting" $sysctl_file; then
    printf "\n\n\n*********Setting $max_map_count_setting already exists in $sysctl_file."
else
    # Add the setting to sysctl.conf
    bash -c "echo -e \"$max_map_count_setting\" >> $sysctl_file"
    echo "Setting $max_map_count_setting added to $sysctl_file."
    # Apply the changes
    sysctl -p
    printf "\n\n\n*********Changes applied using sysctl vm.max_map_count = 262144\n\n"
fi

printf "\n\n\n*********Sleeping 20 seconds to give dpkg time to clean up...\n\n"
sleep 20s

printf "\n\n\n*********Installing ElasticSearch...\n\n"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list || handle_error "Failed to add Elasticsearch GPG key." "${LINENO}"
elastic_install_log=$(apt-get -qq update && apt-get -qq install elasticsearch | stdbuf -oL tee /dev/tty) || handle_error "Failed to install Elasticsearch." "${LINENO}"
elastic_password=$(echo "$elastic_install_log" | awk -F' : ' '/The generated password for the elastic built-in superuser/{print $2}') 
elastic_password=$(echo -n "$elastic_password" | tr -cd '[:print:]')
printf "\n\n\n*********Elastic password is $elastic_password\n\n"

printf "\n\n\n*********Enabling and starting ElasticSearch service...\n\n"
systemctl daemon-reload && systemctl enable elasticsearch.service && systemctl start elasticsearch.service

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
kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" "#server.host: \"localhost\"" "server.host: \"0.0.0.0\"" "${LINENO}"

printf "\n\n\n*********Configuring Kibana - set elasticsearch.hosts to 0.0.0.0 instead of DHCP IP\n\n"
kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" "elasticsearch.hosts: \['https:\/\/[^']*'\]" "elasticsearch.hosts: \['https:\/\/0.0.0.0:9200'\]" "${LINENO}"

printf "\n\n\n*********Enrolling Kibana with Elastic...\n\n"
/usr/share/kibana/bin/kibana-setup --enrollment-token $kibana_token

printf "\n\n\n*********Enabling and starting Kibana service...\n\n"
systemctl daemon-reload && systemctl enable kibana.service && systemctl start kibana.service

printf "\n\n\n*********Sleeping 20 seconds to give dpkg time to clean up...\n\n"
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
path="/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
replace_text "$path" 'Environment="EF_LICENSE_ACCEPTED=false"' 'Environment="EF_LICENSE_ACCEPTED=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_ELASTICSEARCH_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_ELASTICSEARCH_PASSWORD=changeme"' "Environment=\"EF_OUTPUT_ELASTICSEARCH_PASSWORD=$elastic_password\"" "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION=false"' 'Environment="EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION=true"' "${LINENO}"

printf "\n\n\n*********Enabling and starting ElastiFlow service...\n\n"
#Start Elastiflow flow collector
systemctl daemon-reload && systemctl enable flowcoll.service && systemctl start flowcoll.service

#Install Elastiflow SNMP collector
#wget https://elastiflow-releases.s3.us-east-2.amazonaws.com/snmp-collector/snmp-collector_6.4.2_linux_amd64.deb
#apt install ./snmp-collector_6.4.2_linux_amd64.deb
#systemctl daemon-reload && systemctl enable snmpcoll.service && systemctl start snmp.service

printf "\n\n\n*********Downloading and installing ElastiFlow flow dashboards\n\n"
git clone https://github.com/elastiflow/elastiflow_for_elasticsearch.git /etc/elastiflow_for_elasticsearch/
response=$(curl -X POST -u elastic:$elastic_password "localhost:5601/api/saved_objects/_import?createNewCopies=true" -H "kbn-xsrf: true" --form file=@/etc/elastiflow_for_elasticsearch/kibana/flow/kibana-8.2.x-flow-ecs.ndjson -H 'kbn-xsrf: true')

success=$(echo "$response" | jq -r '.success')

if [ "$success" == "true" ]; then
    echo "Flow dashboards installed successfully\n\n"
else
    echo "Not successful"
fi

#printf "\n\n\n*********Clean up - Shutting down machine\n\n"
#shutdown -h now

#printf "\n\n\n*********Elastic trial license started\n\n"
#curl -X POST -k 'https://localhost:9200/_license/start_trial?acknowledge=true' -u elastic:$elastic_password

printf "\n\nGo to http://host_ip:5601 (elastic / elastic)\n\n"

printf "\n\n\n*********\nAll done.\n\n"

printf "\n\n\n*********Clean up - Command history purged\n\n"
history -c && history -w

printf "\n\n\n*********Clean up - Deleting setup files...\n\n"
rm -rf ~/elastiflow_update/
rm -rf ~/ef_va/
