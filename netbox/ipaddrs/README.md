This python script uses the Netbox API to get useful information to augment flowcoll by writing information for device IPs to the ipaddrs.yml. This script uses two API endpoints /api/dcim/devices/ and /api/dcim/sites/. This includes extracting results[].manufacturer.name, results[].role.name, results[].site.name, results[].latitude, results[].logitude, results[]. results[].primary_ip4.address and from the sites endpoint results[].physical_address. This script will site site.name to look up the address from the sites endpoint. If any of these values do not exist in Netbox the entry will be left blank. 

Update the following in the script to match your environment 

API_TOKEN = '9efdcab9667d7314eb73157c839cd6c970ab5718'  # Replace with your actual API token

NETBOX_API_URL = 'http://192.168.1.6:8000/api/dcim/devices/'

SITES_API_URL = 'http://192.168.1.6:8000/api/dcim/sites/'

to run

python3 import_mappings.py

Example output

192.168.2.1/24:
  tags:
  - Router
  metadata:
    company.site.name: greer_office
    device.type.name: Ubiquiti
    .geo.loc.coord: 34.938728,82.227057
    .geo.city.name: Greer
    .geo.country.code: US
    .geo.tz.name: America/New_York
192.168.1.129/24:
  tags:
  - Server
  metadata:
    company.site.name: Autodiscovered devices
    device.type.name: UNRAID
