#!/bin/bash

elastiflow_version="6.4.2"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="yourStrongPassword123!"

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

#Install the necessary packages.
 apt-get update &&  apt-get -y install lsb-release ca-certificates curl gnupg2

#Import the public GPG key. This key is used to verify that the APT repository is signed.
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp |  gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring

#Create an APT repository for OpenSearch:
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" |  tee /etc/apt/sources.list.d/opensearch-2.x.list

#Verify that the repository was created successfully. #Unless otherwise indicated, the latest available version of OpenSearch is installed.
apt-get update &&  apt-get -y install opensearch

#With the repository information added, list all available versions of OpenSearch:
# apt list -a opensearch

#To install a specific version of OpenSearch:
# Specify the version manually using opensearch=<version>
# apt-get install opensearch=2.11.1

#Once complete, enable OpenSearch.
 systemctl enable opensearch && systemctl start opensearch

#test
#curl -X GET https://localhost:9200 -u 'admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"' --insecure
#curl -X GET https://localhost:9200/_cat/plugins?v -u 'admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"' --insecure

printf "\n\n\n*********Configuring OpenSearch - set 0.0.0.0 as network.host\n\n"
config_path="/etc/opensearch/opensearch.yml"
replace_text "$config_path" "#network.host: 192.168.0.1" "network.host: localhost" "${LINENO}"

# Bind OpenSearch to the correct network interface. Use 0.0.0.0
# to include all available interfaces or specify an IP address
# assigned to a specific interface.
# network.host: 0.0.0.0

# Unless you have already configured a cluster, you should set
# discovery.type to single-node, or the bootstrap checks will
# fail when you try to start the service.
echo "discovery.type: single-node" |  tee -a "$config_path"

# If you previously disabled the Security plugin in opensearch.yml,
# be sure to re-enable it. Otherwise you can skip this setting.
#plugins.security.disabled: false

#Modify the values for initial and maximum heap sizes. As a starting point, you should set these values to half of the available system memory. For dedicated hosts this value can be increased based on your workflow requirements.
#As an example, if the host machine has 8 GB of memory, then you might want to set the initial and maximum heap sizes to 4 GB:
config_path="/etc/opensearch/jvm.options"
replace_text "$config_path" '## -Xms4g' '-Xms4g' "${LINENO}"
replace_text "$config_path" '## -Xmx4g' '-Xmx4g' "${LINENO}"

 systemctl enable opensearch && systemctl start opensearch

#############install opensearch dashboards
#Install the necessary packages.
 apt-get update &&  apt-get -y install lsb-release ca-certificates curl gnupg2

#Import the public GPG key. This key is used to verify that the APT repository is signed.
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp |  gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring

echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/apt stable main" |  tee /etc/apt/sources.list.d/opensearch-dashboards-2.x.list

 apt-get update &&  apt-get -y install opensearch-dashboards
# apt list -a opensearch-dashboards

config_path="/etc/opensearch-dashboards/opensearch_dashboards.yml"
#Specify a network interface that OpenSearch Dashboards should bind to.
# Use 0.0.0.0 to bind to any available interface.
replace_text "$config_path" '# server.host: "localhost"' 'server.host: "0.0.0.0"' "${LINENO}"

 systemctl enable opensearch-dashboards && systemctl start opensearch-dashboards

printf "\n\n\n*********Downloading and installing ElastiFlow Flow Collector...\n\n" 
#Install Elastiflow flow collector
wget -O flow-collector_"$elastiflow_version"_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_"$elastiflow_version"_linux_amd64.deb
apt-get -qq install libpcap-dev
apt-get -qq install ./flow-collector_"$elastiflow_version"_linux_amd64.deb

printf "\n\n\n*********Configuring ElastiFlow Flow Collector...\n\n" 
path="/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
replace_text "$path" 'Environment="EF_LICENSE_ACCEPTED=false"' 'Environment="EF_LICENSE_ACCEPTED=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_OPENSEARCH_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_OPENSEARCH_ECS_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_ECS_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_OPENSEARCH_TLS_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_TLS_ENABLE=true"' "${LINENO}"
replace_text "$path" 'Environment="EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION=false"' 'Environment="EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION=true"' "${LINENO}"

 systemctl enable flowcoll.service && systemctl start flowcoll.service

printf "\n\n\n*********Downloading and installing ElastiFlow flow dashboards\n\n"
git clone https://github.com/elastiflow/elastiflow_for_opensearch.git /etc/elastiflow_for_opensearch/

### for some reason, in order to push dashboards to opensearch, you have to push them as a tenant, which the steps below do.

#create tenants using opensearch documented REST API
curl -k -XPUT -H'content-type: application/json' https://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:9200/_plugins/_security/api/tenants/tenant_one -d '{"description": "tenant one"}'
#curl -k -XPUT -H'content-type: application/json' https://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:9200/_plugins/_security/api/tenants/tenant_two -d '{"description": "tenant two"}'

#login to opensearch-dashboards and save the cookie.
curl -k -XGET -u 'admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"' -c dashboards_cookie http://localhost:5601/api/login/
curl -k -XGET -b dashboards_cookie http://localhost:5601/api/v1/configuration/account | jq

#switch tenant. note the tenant is kept inside the cookie so we need to save it after this request
curl -k -XPOST -b dashboards_cookie -c dashboards_cookie -H'osd-xsrf: true' -H'content-type: application/json' http://localhost:5601/api/v1/multitenancy/tenant -d '{"tenant": "tenant_one", "username": "admin"}'
curl -k -XGET -b dashboards_cookie http://localhost:5601/api/v1/configuration/account | jq

#push the dashboard using the same cookie
response=$(curl -k -XPOST -H'osd-xsrf: true' -b dashboards_cookie http://localhost:5601/api/saved_objects/_import?overwrite=true --form file=@/etc/elastiflow_for_opensearch/dashboards/flow/dashboards-2.0.x-flow-ecs.ndjson)

success=$(echo "$response" | jq -r '.success')

if [ "$success" == "true" ]; then
    printf "Flow dashboards installed successfully\n\n"
else
    printf "Not successful\n\n"
fi

printf "\n\nGo to http://host_ip:5601 (admin / "$OPENSEARCH_INITIAL_ADMIN_PASSWORD")\n\n"
printf "Use \"Tenant 1\""

printf "\n\n\n*********\nAll done.\n\n"
