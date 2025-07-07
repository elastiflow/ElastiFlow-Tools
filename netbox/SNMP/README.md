NetBox to ElastiFlow SNMP Device Configuration Export

This Python script extracts SNMP-relevant device data from a NetBox instance and generates a devices_output.yml file compatible with ElastiFlow's SNMP Collector device.yml format.

🔍 Overview

This utility helps automate SNMP polling configuration in ElastiFlow by using device metadata stored in NetBox. The script fetches basic fields like IP, role, and manufacturer and assigns SNMP settings including credentials, port, and device group classification.


Steps

Populate NetBox with accurate role and manufacturer data.

Edit the config.ini to include your NetBox API token, endpoint, and SNMP settings.

Run the script to produce devices_output.yml.

Copy the resulting file to your ElastiFlow SNMP Collector as device.yml.



Files

import_snmp_devices.py – Main script for NetBox SNMP export.

config.ini – Configuration file containing API and SNMP settings.

devices_output.yml – Output file ready for use with ElastiFlow SNMP collector.



Configuration

Edit config.ini before running the script:

[api]
url = http://<netbox-host>/api/dcim/devices/
token = <your-netbox-api-token>

[snmp]
version = 2c
community = public

; For SNMPv3
username = snmpuser
authentication_protocol = SHA
authentication_passphrase = your_auth_pass
privacy_protocol = AES
privacy_passphrase = your_priv_pass



Data Fields Used

From /api/dcim/devices/, the script extracts:

name – used as a key in the YAML

primary_ip4.address – used as the IP target (strips CIDR)

role.name – used to categorize as Router, Switch, or Firewall

device_type.manufacturer.name – used to assign a device_group

🔎 Note: Only Router, Switch, and Firewall roles are supported in the current version. Model-based refinement is not yet implemented.



Running the Script

python3 import_snmp_devices.py

Upon success, it will print and save devices_output.yml in the current directory.

📄 Sample Output (devices_output.yml)

router-nyc-01:
  device_groups:
    - cisco_c1000
  exponential_timeout: false
  ip: 192.168.1.10
  poll_interval: 60
  port: 164
  retries: 2
  timeout: 1000
  version: 2c
  communities:
    - public



Notes

SNMPv2 and SNMPv3 are both supported; configure via config.ini.

Devices missing required role or manufacturer data are skipped.

Device group logic is based on static mapping from role + manufacturer.

The script does not yet consider the device model field.

Use this command to validate your NetBox API data:

curl -s -H "Authorization: Token <your-token>" \
     -H "Accept: application/json; indent=4" \
     http://<netbox-host>:8000/api/dcim/devices/ | jq .



Future Improvements

Add device model-based group classification

Handle pagination and larger NetBox datasets

Enhanced error handling and debug logging
