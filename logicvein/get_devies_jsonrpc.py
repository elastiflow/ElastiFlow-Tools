#!/usr/bin/env python3

import os
import json
import yaml
from collections import defaultdict
from jsonrpc import JsonRpcProxy

# Load config
with open('config.json') as f:
    config = json.load(f)

URL = config['logicvein_url']
USERNAME = config['logicvein_username']
PASSWORD = config['logicvein_password']
SNMP_VERSION = config['snmp_version']
DEVICE_GROUPS_PATH = '/etc/elastiflow/snmp/device_groups'
NETWORK_NAME = config.get('logicvein_network', 'Default')
SUBNET_QUERY = config.get('logicvein_query', '10.0.0.0/24')

# Connect to LogicVein NetLD via built-in SDK
netld = JsonRpcProxy.fromHost(URL.replace("https://", "").replace("http://", ""), USERNAME, PASSWORD)

# Normalize helper
def normalize(s):
    return s.lower().replace("/", "_").replace("-", "_").replace(" ", "_")

# Load device groups
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

# Vendor aliases and hints
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

VENDOR_HINTS = {
    "cisco": {"c9300": "cisco_cat_9300", "csr1000v": "cisco_csr_1k", "1921": "cisco_isr_1900", "c1921": "cisco_isr_1900"},
    "paloalto": {"pa-vm": "paloalto_firewall", "pa": "paloalto_firewall"},
    "fortinet": {"fortigate": "fortinet_fortigate", "vm64": "fortinet_fortigate"},
    "arista": {"veos": "arista"},
    "hp": {"arubaos-cx": "generic"},
    "apc": {"smart": "generic"},
    "dell": {"s3100": "dell_emc_s4000", "fes": "dell_emc_s4000"},
    "f5": {"bigip": "f5_bigip", "virtualedition": "f5_bigip"},
    "infoblox": {"ib-vmware": "generic"}
}

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

# Search inventory
search_result = netld.call('Inventory.search', NETWORK_NAME, 'ipAddress', SUBNET_QUERY, {
    'offset': 0,
    'pageSize': 1000
}, 'ipAddress', False)

devices = search_result.get('devices', [])

# Write YAML
with open("devices.yml", "w") as outfile:
    for device in devices:
        if not isinstance(device, dict):
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
            outfile.write(f"    - username: {USERNAME}\n")
            outfile.write(f"      authentication_protocol: {v3['authentication_protocol']}\n")
            outfile.write(f"      authentication_passphrase: {v3['authentication_passphrase']}\n")
            outfile.write(f"      privacy_protocol: {v3['privacy_protocol']}\n")
            outfile.write(f"      privacy_passphrase: {v3['privacy_passphrase']}\n")
        outfile.write("\n")

# Logout
netld.call('Security.logoutCurrentUser')