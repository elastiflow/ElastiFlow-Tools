import requests
import yaml
import configparser

# Read configuration
config = configparser.ConfigParser()
config.read('config.ini')

api_url = config['api']['url']
api_token = config['api']['token']

snmp_version = config['snmp']['version']

# Define mapping for device groups based on role and manufacturer
device_group_mapping = {
    "Router": {
        "Ubiquiti": "ubiquiti_edgemax",
        "Cisco": "cisoc_c1000",
        "Juniper": "juniper_ex",
        "Arista": "arista"
    },
    "Switch": {
        "Ubiquiti": "ubiquiti_edgemax",
        "Cisco": "cisoc_c1000",
        "Juniper": "juniper_ex",
        "Arista": "arista"
    },
    "Firewall": {
        "Palo Alto": "paloalto_firewall",
        "Calix": "calix_axos"
    }
}

# Function to process each device
def process_device(device):
    role_name = device["role"]["name"]
    manufacturer_name = device["device_type"]["manufacturer"]["name"]
    
    if role_name not in device_group_mapping:
        return None

    device_group = device_group_mapping.get(role_name, {}).get(manufacturer_name)
    
    if device_group:
        device_entry = {
            "device_groups": [device_group],
            "exponential_timeout": False,
            "ip": device["primary_ip4"]["address"].split("/")[0],
            "poll_interval": 60,
            "port": 164,
            "retries": 2,
            "timeout": 1000,
            "version": snmp_version
        }

        # Add SNMP version-specific configurations
        if snmp_version == "2c":
            device_entry["communities"] = [config['snmp']['community']]
        elif snmp_version == "3":
            device_entry["v3_credentials"] = [{
                "username": config['snmp']['username'],
                "authentication_protocol": config['snmp']['authentication_protocol'],
                "authentication_passphrase": config['snmp']['authentication_passphrase'],
                "privacy_protocol": config['snmp']['privacy_protocol'],
                "privacy_passphrase": config['snmp']['privacy_passphrase']
            }]

        return {device["name"]: device_entry}
    
    return None

# Make the REST API call
headers = {
    'Authorization': f'Token {api_token}',
    'Accept': 'application/json; indent=4',
}

response = requests.get(api_url, headers=headers)
response.raise_for_status()

# Process the response JSON
data = response.json()

# Process each device and build the YAML structure
output_data = {}
for device in data["results"]:
    processed_device = process_device(device)
    if processed_device:
        output_data.update(processed_device)

# Convert the output data to YAML format
output_yaml = yaml.dump(output_data, default_flow_style=False)

# Print the output YAML (or save to a file)
print(output_yaml)

# Optionally, save the YAML output to a file
with open("devices_output.yml", "w") as file:
    yaml.dump(output_data, file, default_flow_style=False)