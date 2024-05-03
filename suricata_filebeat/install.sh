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
curl -sS -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.13.3-amd64.deb
dpkg -i filebeat-8.13.3-amd64.deb

printf "Obtaining CA fingerprint…\n\n"
cert_file="/etc/elasticsearch/certs/http_ca.crt"
# Extract the fingerprint, convert to lowercase, and remove colons
fingerprint=$(openssl x509 -fingerprint -sha256 -in "$cert_file" | awk -F= '/Fingerprint/ {print tolower($2)}' | tr -d ':')
echo "Fingerprint: $fingerprint"

config_file="/etc/filebeat/filebeat.yml"
cp $config_file ${config_file}_old
sed -i '/^ *output.elasticsearch:$/,/^ *hosts: \["localhost:9200"\]/ {
  /^ *hosts: \["localhost:9200"\]/ a \
  username: "elastic"\
  password: "elastic"\
  protocol: "https"\
  ssl:\
    enabled: true\
    ca_trusted_fingerprint: "'"${fingerprint}"'"
}' "$config_file"


printf "Enabling Suricata...\n\n"
 filebeat modules enable suricata

printf "Configuring Suricata Filebeat to look at eve.log file\n\n"
# sed -i '/^ *eve:$/,/^ *enabled: false$/ s/^ *eve:$/  eve:\n    enabled: false\n  var.paths: ["\/var\/log\/suricata\/eve.json"]/' /etc/filebeat/modules.d/suricata.yml
 sed -i '/^\s*eve:$/,/^\s*enabled: false$/ {
  /^\s*enabled: false$/ {
    s/false/true/
    a \
    var.paths: ["/var/log/suricata/eve.json"]
  }
}' /etc/filebeat/modules.d/suricata.yml

printf "Running the filebeat setup (this will create the filebeat indexes, dashboards etc. in Elasticsearch)\n\n"
filebeat setup -e > /dev/null 2>&1

printf "Starting filebeat...\n"
service filebeat start

sleep 10

printf "Checking if Filebeat service is active...\n\n"
service_name="filebeat"
if systemctl is-active --quiet "$service_name"; then
    echo "The $service_name service is active (running)."
else
    echo "The $service_name service is not active."
fi

printf "triggering test threats...\n\n"
url="http://testmynids.org/uid/index.html"
for ((i = 1; i <= 4; i++)); do
    curl -sS "$url" -o /dev/null
    sleep 2
done

#printf "Checking if 4 test threats have been found:\n\n"

# Make the curl call and capture the output
#output=$(curl -sS -k -X GET "https://localhost:9200/filebeat-*/_search" -u elastic:elastic -H 'Content-Type: application/json' -d'
#{
#  "query": {
#    "match_phrase": {
#      "rule.name": "GPL ATTACK_RESPONSE id check returned root"
#    }
#  }
#}')

# Get the total hits value using jq
#total_hits=$(echo "$output" | jq '.hits.total.value')

# Check if total hits is exactly 4 and print the appropriate message with color
#if [ "$total_hits" -eq 4 ]; then
#    printf "\033[32mAlerts found in Elastic!\033[0m\n"
#else
#    printf "\033[31Alerts not found in Elastic. Something's wrong\033[0m\n"
#fi


printf "All done.\n\n"
printf 'Check Kibana dashboard "[Filebeat Suricata] Alert Overview" for 4 alerts with the following information:\n'
printf "Alert signature: GPL ATTACK_RESPONSE id check returned root\n"
printf "Alert category: Potentially Bad Traffic\n\n"
