import json
import subprocess
import os
import yaml
import urllib.parse
from collections import defaultdict

# Load config
with open('config.json') as f:
    config = json.load(f)

API_URL = config['logicvein_url'] + '/rest'
LOGICVEIN_USERNAME = config['logicvein_username']
LOGICVEIN_PASSWORD = config['logicvein_password']
SNMP_VERSION = config['snmp_version']
DEVICE_GROUPS_PATH = '/etc/elastiflow/snmp/device_groups'

# URL-encode password
encoded_password = urllib.parse.quote(LOGICVEIN_PASSWORD)

# Build login URL
login_url = f"{config['logicvein_url']}/jsonrpc?j_username={LOGICVEIN_USERNAME}&j_password={encoded_password}"

# Authenticate and save cookies
auth_result = subprocess.run(
    ["curl", "-s", "-c", "cookies.txt", login_url],
    capture_output=True,
    text=True
)

if auth_result.returncode != 0:
    print("ERROR: curl failed to run.")
    exit(1)

if os.path.exists("cookies.txt") and os.path.getsize("cookies.txt") < 200:
    print("WARNING: cookies.txt may be empty or invalid. Login likely failed.")

# Normalize helper
def normalize(s):
    return s.lower().replace("/", "_").replace("-", "_").replace(" ", "_")

# Load device groups per vendor
device_groups_by_vendor = defaultdict(list)
for filename in os.listdir(DEVICE_GROUPS_PATH):
    if filename.endswith(".yml"):
        vendor = os.path.splitext(filename)[0].lower()
        path = os.path.join(DEVICE_GROUPS_PATH, filename)
        try:
            with open(path) as f:
                data = yaml.safe_load(f)
                if isinstance(data, dict):
                    device_groups_by_vendor[vendor].extend(data.keys())
        except Exception as e:
            print(f"Warning: Failed to parse {filename}: {e}")

# Vendor aliases to normalize inconsistent names
VENDOR_ALIAS = {
    "paloalto networks": "paloalto",
    "f5 networks": "f5",
    "aruba": "hp",
    "foundry": "dell",
    "extreme": "extreme",
    "riverbed": "riverbed",
    "infoblox": "infoblox",
    "h3c": "h3c"
}

# Vendor-specific model hints
VENDOR_HINTS = {
    "cisco": {
        "c9300": "cisco_cat_9300",
        "csr1000v": "cisco_csr_1k",
        "1921": "cisco_isr_1900",
        "c1921": "cisco_isr_1900"
    },
    "paloalto": {
        "pa-vm": "paloalto_firewall",
        "pa": "paloalto_firewall"
    },
    "fortinet": {
        "fortigate": "fortinet_fortigate",
        "vm64": "fortinet_fortigate"
    },
    "arista": {
        "veos": "arista"
    },
    "hp": {
        "arubaos-cx": "generic"
    },
    "apc": {
        "smart": "generic"
    },
    "dell": {
        "s3100": "dell_emc_s4000",
        "fes": "dell_emc_s4000"
    },
    "f5": {
        "bigip": "f5_bigip",
        "virtualedition": "f5_bigip"
    },
    "infoblox": {
        "ib-vmware": "generic"
    }
}

# Guess vendor if missing
def guess_vendor_from_model(model):
    model_lower = model.lower()
    if model_lower.startswith("cisco") or model_lower.startswith("c"):
        return "cisco"
    if "pa" in model_lower:
        return "paloalto"
    if "fg" in model_lower:
        return "fortinet"
    if "veos" in model_lower or "arista" in model_lower:
        return "arista"
    if "s3100" in model_lower or "fes" in model_lower:
        return "dell"
    if "smart" in model_lower:
        return "apc"
    return "generic"

# Match device group
def match_device_group(model, adapter_id, vendor):
    norm_model = normalize(model)
    norm_vendor = normalize(vendor)
    candidate_groups = device_groups_by_vendor.get(norm_vendor, [])

    for group in candidate_groups:
        if normalize(group) in norm_model or norm_model in normalize(group):
            return group

    for keyword, group in VENDOR_HINTS.get(norm_vendor, {}).items():
        if keyword in norm_model:
            return group

    return "generic"

# Call Inventory.search
curl_command = [
    "curl", "-s", "-X", "POST", API_URL,
    "-H", "Content-Type: application/json",
    "-b", "cookies.txt",
    "-d", json.dumps({
        "jsonrpc": "2.0",
        "method": "Inventory.search",
        "params": {
            "network": ["Default"],
            "scheme": "ipAddress",
            "query": "10.0.0.0/24",
            "pageData": {
                "offset": 0,
                "pageSize": 1000
            },
            "sortColumn": "ipAddress",
            "descending": False
        },
        "id": 1
    })
]

result = subprocess.run(curl_command, capture_output=True, text=True)
if result.stderr:
    print("curl stderr:", result.stderr)

try:
    response_data = json.loads(result.stdout)
    devices = response_data.get("result", {}).get("devices", [])
except json.JSONDecodeError:
    print("Failed to decode JSON. Response was:")
    print(result.stdout)
    exit(1)

# Write output YAML
with open("devices.yml", "w") as outfile:
    for device in devices:
        if not isinstance(device, dict):
            print(f"Skipping unexpected item: {device}")
            continue

        hostname = device.get("hostname", "UNKNOWN")
        ip_address = device.get("ipAddress", "0.0.0.0")
        adapter_id = device.get("adapterId", "unknown_group").replace("::", "_").lower()
        model = device.get("model", "").strip()
        raw_vendor = device.get("softwareVendor", "").strip().lower()
        vendor = VENDOR_ALIAS.get(raw_vendor, raw_vendor) or guess_vendor_from_model(model)

        matched_device_group = match_device_group(model, adapter_id, vendor)

        print(f"DEBUG: {hostname=} {model=} {vendor=} {adapter_id=} -> {matched_device_group=}")

        outfile.write(f"{hostname}:\n")
        if SNMP_VERSION == '2c':
            community = config.get('snmp_community', 'public')
            outfile.write("  communities:\n")
            outfile.write(f"  - {community}\n")
        outfile.write("  device_groups:\n")
        outfile.write(f"  - {matched_device_group}\n")
        outfile.write("  exponential_timeout: false\n")
        outfile.write(f"  ip: {ip_address}\n")
        outfile.write("  poll_interval: 30\n")
        outfile.write("  port: 161\n")
        outfile.write("  retries: 2\n")
        outfile.write("  timeout: 10000\n")

        if SNMP_VERSION == '2c':
            outfile.write("  version: 2c\n")
        elif SNMP_VERSION == '3':
            v3 = config['snmpv3']
            outfile.write("  v3_credentials:\n")
            outfile.write("    - username: {}\n".format(LOGICVEIN_USERNAME))
            outfile.write("      authentication_protocol: {}\n".format(v3['authentication_protocol']))
            outfile.write("      authentication_passphrase: {}\n".format(v3['authentication_passphrase']))
            outfile.write("      privacy_protocol: {}\n".format(v3['privacy_protocol']))
            outfile.write("      privacy_passphrase: {}\n".format(v3['privacy_passphrase']))
        outfile.write("\n")
egraham@ahead-snmpcoll:~/logicvein$ cat get_device3.py
import json
import subprocess
import os
import yaml
import urllib.parse
from collections import defaultdict

# Load config
with open('config.json') as f:
    config = json.load(f)

API_URL = config['logicvein_url'] + '/rest'
LOGICVEIN_USERNAME = config['logicvein_username']
LOGICVEIN_PASSWORD = config['logicvein_password']
SNMP_VERSION = config['snmp_version']
DEVICE_GROUPS_PATH = '/etc/elastiflow/snmp/device_groups'
NETWORK_NAME = config.get('logicvein_network', 'Default')

# URL-encode password
encoded_password = urllib.parse.quote(LOGICVEIN_PASSWORD)

# Build login URL
login_url = f"{config['logicvein_url']}/jsonrpc?j_username={LOGICVEIN_USERNAME}&j_password={encoded_password}"

# Authenticate and save cookies
auth_result = subprocess.run(["curl", "-s", "-c", "cookies.txt", login_url], capture_output=True, text=True)
if auth_result.returncode != 0:
    print("ERROR: curl failed to run.")
    exit(1)
if os.path.exists("cookies.txt") and os.path.getsize("cookies.txt") < 200:
    print("WARNING: cookies.txt may be empty or invalid. Login likely failed.")

# Normalize helper
def normalize(s):
    return s.lower().replace("/", "_").replace("-", "_").replace(" ", "_")

# Load device groups per vendor
device_groups_by_vendor = defaultdict(list)
for filename in os.listdir(DEVICE_GROUPS_PATH):
    if filename.endswith(".yml"):
        vendor = os.path.splitext(filename)[0].lower()
        path = os.path.join(DEVICE_GROUPS_PATH, filename)
        try:
            with open(path) as f:
                data = yaml.safe_load(f)
                if isinstance(data, dict):
                    device_groups_by_vendor[vendor].extend(data.keys())
        except Exception as e:
            print(f"Warning: Failed to parse {filename}: {e}")

# Vendor aliases
VENDOR_ALIAS = {
    "paloalto networks": "paloalto",
    "f5 networks": "f5",
    "aruba": "hp",
    "foundry": "dell",
    "extreme": "extreme",
    "riverbed": "riverbed",
    "infoblox": "infoblox",
    "h3c": "h3c"
}

# Vendor-specific model hints
VENDOR_HINTS = {
    "cisco": {
        "c9300": "cisco_cat_9300",
        "csr1000v": "cisco_csr_1k",
        "1921": "cisco_isr_1900",
        "c1921": "cisco_isr_1900"
    },
    "paloalto": {
        "pa-vm": "paloalto_firewall",
        "pa": "paloalto_firewall"
    },
    "fortinet": {
        "fortigate": "fortinet_fortigate",
        "vm64": "fortinet_fortigate"
    },
    "arista": {
        "veos": "arista"
    },
    "hp": {
        "arubaos-cx": "generic"
    },
    "apc": {
        "smart": "generic"
    },
    "dell": {
        "s3100": "dell_emc_s4000",
        "fes": "dell_emc_s4000"
    },
    "f5": {
        "bigip": "f5_bigip",
        "virtualedition": "f5_bigip"
    },
    "infoblox": {
        "ib-vmware": "generic"
    }
}

# Guess vendor from model
def guess_vendor_from_model(model):
    model_lower = model.lower()
    if model_lower.startswith("cisco") or model_lower.startswith("c"):
        return "cisco"
    if "pa" in model_lower:
        return "paloalto"
    if "fg" in model_lower:
        return "fortinet"
    if "veos" in model_lower or "arista" in model_lower:
        return "arista"
    if "s3100" in model_lower or "fes" in model_lower:
        return "dell"
    if "smart" in model_lower:
        return "apc"
    return "generic"

# Match device group
def match_device_group(model, adapter_id, vendor):
    norm_model = normalize(model)
    norm_vendor = normalize(vendor)
    candidate_groups = device_groups_by_vendor.get(norm_vendor, [])
    for group in candidate_groups:
        if normalize(group) in norm_model or norm_model in normalize(group):
            return group
    for keyword, group in VENDOR_HINTS.get(norm_vendor, {}).items():
        if keyword in norm_model:
            return group
    return "generic"

# Inventory.search request
curl_command = [
    "curl", "-s", "-X", "POST", API_URL,
    "-H", "Content-Type: application/json",
    "-b", "cookies.txt",
    "-d", json.dumps({
        "jsonrpc": "2.0",
        "method": "Inventory.search",
        "params": {
            "network": [NETWORK_NAME],
            "scheme": "ipAddress",
            "query": "10.0.0.0/24",
            "pageData": {"offset": 0, "pageSize": 100},
            "sortColumn": "ipAddress",
            "descending": False
        },
        "id": 1
    })
]

result = subprocess.run(curl_command, capture_output=True, text=True)
if result.stderr:
    print("curl stderr:", result.stderr)

try:
    response_data = json.loads(result.stdout)
    devices = response_data.get("result", {}).get("devices", [])
except json.JSONDecodeError:
    print("Failed to decode JSON. Response was:")
    print(result.stdout)
    exit(1)

# Write devices.yml
with open("devices.yml", "w") as outfile:
    for device in devices:
        if not isinstance(device, dict):
            print(f"Skipping unexpected item: {device}")
            continue

        hostname = device.get("hostname", "UNKNOWN")
        ip_address = device.get("ipAddress", "0.0.0.0")
        adapter_id = device.get("adapterId", "unknown_group").replace("::", "_").lower()
        model = device.get("model", "").strip()
        raw_vendor = device.get("softwareVendor", "").strip().lower()
        vendor = VENDOR_ALIAS.get(raw_vendor, raw_vendor) or guess_vendor_from_model(model)
        matched_device_group = match_device_group(model, adapter_id, vendor)

        print(f"DEBUG: {hostname=} {model=} {vendor=} {adapter_id=} -> {matched_device_group=}")

        outfile.write(f"{hostname}:\n")
        if SNMP_VERSION == '2c':
            community = config.get('snmp_community', 'public')
            outfile.write("  communities:\n")
            outfile.write(f"  - {community}\n")
        outfile.write("  device_groups:\n")
        outfile.write(f"  - {matched_device_group}\n")
        outfile.write("  exponential_timeout: false\n")
        outfile.write(f"  ip: {ip_address}\n")
        outfile.write("  poll_interval: 30\n")
        outfile.write("  port: 161\n")
        outfile.write("  retries: 2\n")
        outfile.write("  timeout: 10000\n")

        if SNMP_VERSION == '2c':
            outfile.write("  version: 2c\n")
        elif SNMP_VERSION == '3':
            v3 = config['snmpv3']
            outfile.write("  v3_credentials:\n")
            outfile.write(f"    - username: {LOGICVEIN_USERNAME}\n")
            outfile.write(f"      authentication_protocol: {v3['authentication_protocol']}\n")
            outfile.write(f"      authentication_passphrase: {v3['authentication_passphrase']}\n")
            outfile.write(f"      privacy_protocol: {v3['privacy_protocol']}\n")
            outfile.write(f"      privacy_passphrase: {v3['privacy_passphrase']}\n")
        outfile.write("\n")
