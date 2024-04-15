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

printf "\n\n\n*********Disable memory paging and swapping...\n\n"
swapoff -a
bootstrap.memory_lock=true
# Make a copy of /etc/fstab
cp /etc/fstab /etc/fstab_backup
# Prepend a '#' to every line containing the word 'swap' in the backup file
sed -i '/swap/s/^/#/' /etc/fstab

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
echo -e $jvm_options | tee /etc/opensearch/jvm.options.d/heap.options > /dev/null

echo "OpenSearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx."


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

#Configure flowcoll service to stop after 60 seconds when asked to terminate so this does not hold up the system forever on shutdown.
replace_text "/etc/systemd/system/flowcoll.service" "TimeoutStopSec=infinity" "TimeoutStopSec=60" "N/A"

printf "\n\n\n*********Configuring ElastiFlow Flow Collector...\n\n" 
flowcoll_config_path="/etc/systemd/system/flowcoll.service.d/flowcoll.conf"
replace_text "$flowcoll_config_path" 'Environment="EF_LICENSE_ACCEPTED=false"' 'Environment="EF_LICENSE_ACCEPTED=true"' "${LINENO}"
replace_text "$flowcoll_config_path" '#Environment="EF_ACCOUNT_ID="' "Environment=\"EF_ACCOUNT_ID=$elastiflow_account_id\"" "${LINENO}"
replace_text "$flowcoll_config_path" '#Environment="EF_FLOW_LICENSE_KEY="' "Environment=\"EF_FLOW_LICENSE_KEY=$elastiflow_flow_license_key\"" "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_OPENSEARCH_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_OPENSEARCH_ECS_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_ECS_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_OPENSEARCH_TLS_ENABLE=false"' 'Environment="EF_OUTPUT_OPENSEARCH_TLS_ENABLE=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION=false"' 'Environment="EF_OUTPUT_OPENSEARCH_TLS_SKIP_VERIFICATION=true"' "${LINENO}"
replace_text "$flowcoll_config_path" 'Environment="EF_OUTPUT_OPENSEARCH_PASSWORD=admin"' "Environment=\"EF_OUTPUT_OPENSEARCH_PASSWORD=$OPENSEARCH_INITIAL_ADMIN_PASSWORD\"" "${LINENO}"


systemctl enable flowcoll.service && systemctl start flowcoll.service

printf "\n\n\n*********Downloading and installing ElastiFlow flow dashboards\n\n"
git clone https://github.com/elastiflow/elastiflow_for_opensearch.git /etc/elastiflow_for_opensearch/

### for some reason, in order to push dashboards to opensearch, you have to push them as a tenant, which the steps below do.

#create tenants using opensearch documented REST API
curl -k -XPUT -H'content-type: application/json' https://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:9200/_plugins/_security/api/tenants/tenant_one -d '{"description": "tenant one"}'
#curl -k -XPUT -H'content-type: application/json' https://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:9200/_plugins/_security/api/tenants/tenant_two -d '{"description": "tenant two"}'

#login to opensearch-dashboards and save the cookie.
curl -k -XGET -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" -c dashboards_cookie http://localhost:5601/api/login/
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

version=$(curl -k -XGET https://admin:"yourStrongPassword123!"@localhost:9200 | jq -r '.version.number')
printf "\n\nInstalled OpenSearch Version: $version\n"

version=$(curl -s http://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:5601/api/status | jq -r '.version.number')
printf "Installed OpenSearch Dashboards Version: $version\n"

version=$(/usr/share/elastiflow/bin/flowcoll -version)
printf "Installed ElastiFlow version: $version\n"

version=$(lsb_release -d | awk -F'\t' '{print $2}')
printf "Operating System: $version\n\n"


printf "\e[5;37m\n\nGo to http://$IP_ADDRESS:5601 (admin / "$OPENSEARCH_INITIAL_ADMIN_PASSWORD")\n\n\e[0m"
printf "Use \"Tenant 1\"\n"
printf "Open ElastiFlow dashboard: “ElastiFlow (flow): Overview\"\n\n"

printf "\n\n\n*********\nAll done.\n\n"
