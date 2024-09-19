README

This script and configuration file can be used to extract device details from Netbox and write the data to the ElastiFlow snmp collector device.yml file. This script extracts results[].manufacturer.name, results[].role.name and results[].primary_ip4.address. Along with the values extracted from Netbox the config.ini needs to be configured for SNMP version 2 or 3 and credentails (community for 2 and v3 credentials for v3 - see config.ini). This script has limited device_group identification support and will only do basic mapping not taking into consideration the results[].model, which should be added in a later release. This script also only extracts role.name of Router, Switch and Firewall. The Netbox values we extract need to be in the Netbox config. Running the following curl command can verify this

curl -s -H "Authorization: Token {token}" -H "Accept: application/json; indent=4" http://{netbox}:8000/api/dcim/devices/ | jq .

The script can be run as a python3 script
