This python script uses the Netbox API to get useful information to augment flowcoll by writing information for device IPs to the ipaddrs.yml. This script uses two API endpoints /api/dcim/devices/ and /api/dcim/sites/. This includes extracting results[].manufacturer.name, results[].role.name, results[].site.name, results[].latitude, results[].logitude, results[]. results[].primary_ip4.address and from the sites endpoint results[].physical_address. This script will site site.name to look up the address from the sites endpoint. The physical_address should be in the format  "223 mountain, Greer, SC, 29651, US", <street>,<city>,<state>,<country>,<zip>,<country_code>. If any of the fields used in this script do not exist, or do not have values, in Netbox the entry will be left blank. 

Update the following in the script to match your environment 

API_TOKEN = '9efdcab9667d7314eb73157c839cd6c970ab5718'  # Replace with your actual API token

NETBOX_API_URL = 'http://192.168.1.6:8000/api/dcim/devices/'

SITES_API_URL = 'http://192.168.1.6:8000/api/dcim/sites/'

to run

python3 import_mappings.py

Example output


<img width="332" alt="Screenshot 2024-09-19 at 9 19 39 AM" src="https://github.com/user-attachments/assets/4152b8b0-bfdd-41c2-bf81-42e27d3dd417">
