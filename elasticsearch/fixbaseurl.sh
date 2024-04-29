#!/bin/bash

kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"
