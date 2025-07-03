📱 NetBox to ElastiFlow IP Address Metadata Export

This Python script extracts device and site metadata from a NetBox instance via its API, then formats it into a YAML file (netbox_devices.yml) suitable for use with ElastiFlow’s ipaddrs.yml NetFlow enrichment configuration.

🔍 Overview

Use this tool to enhance your NetFlow or IPFIX records with valuable metadata from your infrastructure inventory managed in NetBox. The resulting YAML file can enrich flow records in ElastiFlow with contextual details such as:

Device roles and types

Site name and location

Geographic coordinates (lat/lon)

Time zone and country info



Steps to implement

1. Identify what metadata from NetBox you want to include in ElastiFlow (site, role, location, etc).

2. Edit the Python script to match your NetBox API URL and token.

3. Run the script to generate netbox_devices.yml.

4. Copy the generated file to your ElastiFlow instance as ipaddrs.yml.


Files

import_mappings.py – Main script that pulls data from NetBox and writes YAML output.

netbox_devices.yml – Output file containing IP address enrichment data for ElastiFlow.


Configuration

In import_mappings.py, update the following variables to match your environment:

API_TOKEN = 'your-netbox-api-token'
NETBOX_API_URL = 'http://<netbox-host>/api/dcim/devices/'
SITES_API_URL = 'http://<netbox-host>/api/dcim/sites/'


Data Fields Collected

From /api/dcim/devices/:

primary_ip4.address – IP address used as the key in the YAML

device_type.manufacturer.name – Manufacturer

role.name – Device role

site.name – Site identifier

latitude and longitude – Optional coordinates

From /api/dcim/sites/ (looked up by site.name):

physical_address – Parsed to extract .geo.city.name and .geo.country.code

time_zone – Stored as .geo.tz.name

Example address format expected:

"223 Mountain Rd, Greer, SC, 29651, US"

🧪 Running the Script

Run the script with:

python3 import_mappings.py

On success, netbox_devices.yml will be generated in the current directory.


Sample Output (netbox_devices.yml)

192.168.1.10:
  tags:
    - core-switch
  metadata:
    company.site.name: site-nyc
    device.type.name: Cisco
    .geo.loc.coord: "40.7128,-74.0060"
    .geo.city.name: New York
    .geo.country.code: US
    .geo.tz.name: America/New_York

👍 Notes

Missing or empty NetBox fields will be skipped (i.e., left blank).

Entries without a valid primary_ip4 or metadata are excluded.

Output file is compatible with the ipaddrs.yml format expected by ElastiFlow’s flow enrichment processor.

🧼 Cleanup & Maintenance

Consider automating the script to run on a schedule if NetBox data changes frequently.

Review ElastiFlow's docs for the latest ipaddrs.yml format support and enrichment behaviors.
