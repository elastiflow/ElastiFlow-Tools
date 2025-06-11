ElastiFlow SNMP collector device map generator for Logicvein inventory

This script automates the discovery and classification of network devices using LogicVein's API and maps them to the appropriate ElastiFlow SNMP devices.yml and device_groups. The output is written to a devices.yml file in a format suitable for ElastiFlow ingestion.

Features

Authenticates to LogicVein portal via API login using provided credentials

Queries device inventory in a specified Logicvein defined "network"

Maps each device to a specific ElastiFlow device_group using:

Vendor-specific group files

Model-based heuristics

Supports SNMP v2c and v3 configuration through config.json settings (2c or 3)

Outputs a ready-to-use devices.yml

Requirements

- Python 3.x

- YAML Python library (pyyaml)

- curl must be available on the system

- ElastiFlow SNMP needs to be installed on the system and /etc/elastiflow/snmp/device_groups need to be present. 

Configuration

All configuration is handled via a config.json file located in the same directory as the script.

Sample config.json

{
  "logicvein_url": "Logicvein_URL",
  "logicvein_username": "your_username",
  "logicvein_password": "your_password",
  "logicvein_network": "Default",
  "snmp_version": "2c",
  "snmp_community": "public",
  "snmpv3": {
    "authentication_protocol": "sha",
    "authentication_passphrase": "authpass",
    "privacy_protocol": "aes",
    "privacy_passphrase": "privpass"
  }
}

Running the Script

python3 generate_devices.py

This will:

Log in to the LogicVein portal using provided credentials

Query device data for the configured network - "Default" is the default 

Attempt to map each device to a matching device_group (this is not perfect and should be reviewed in the output)

Write results to devices.yml

Debug Output

Each processed device logs a debug line such as:

DEBUG: hostname='CSR1000V_17_03_05' model='CSR1000V' vendor='cisco' adapter_id='cisco_ios' -> matched_device_group='cisco_csr_1k'

Example output devices.yml SNMPv2

C9300-24UX:
  communities:
  - public
  device_groups:
  - cisco_cat_9300
  exponential_timeout: false
  ip: 10.0.0.251
  poll_interval: 30
  port: 161
  retries: 2
  timeout: 10000
  version: 2c



Example output devices.yml SNMPv3

C9300-24UX:
  device_groups:
  - cisco_cat_9300
  exponential_timeout: false
  ip: 10.0.0.251
  poll_interval: 30
  port: 161
  retries: 2
  timeout: 10000
  v3_credentials:
    - username: elastiflow
      authentication_protocol: sha
      authentication_passphrase: efauthpassword
      privacy_protocol: des
      privacy_passphrase: efprivpassword


Notes

In the future this script could get SNMP credentials from the API and remove the need for a static configuration. 

If no match is found, the script defaults to device_group: generic

Make sure /etc/elastiflow/snmp/device_groups/ contains valid vendor .yml group files

Authentication issues (e.g., invalid cookies.txt) will print a warning

Output File

devices.yml: Contains all matched device entries with appropriate SNMP config blocks

License

MIT License

Author

Eric Graham