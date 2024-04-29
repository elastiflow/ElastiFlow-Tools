


printf "\n\n\n*********Configuring Kibana - set elasticsearch.hosts to localhost instead of DHCP IP...\n\n"
kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" "elasticsearch.hosts: \['https:\/\/[^']*'\]" "elasticsearch.hosts: \['https:\/\/localhost:9200'\]" "${LINENO}"
replace_text "$kibana_config_path" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"
