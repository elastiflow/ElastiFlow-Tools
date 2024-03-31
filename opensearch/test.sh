
#!/bin/bash

elastiflow_version="6.4.2"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="yourStrongPassword123!"

version=$(curl -s http://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:9200/ | jq -r '.version.number')
print "Installed OpenSearch Version: $version\n"

version=$(curl -s http://admin:"$OPENSEARCH_INITIAL_ADMIN_PASSWORD"@localhost:5601/api/status" | jq -r '.version.number')
print "Installed OpenSearch Dashboards Version: $version\n"

version=$(/usr/share/elastiflow/bin/flowcoll -version)
printf "Installed ElastiFlow version: $version\n"

version=$(lsb_release -d | awk -F'\t' '{print $2}')
printf "Operating System: $version\n\n"
