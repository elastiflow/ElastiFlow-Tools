import os
import argparse
import shutil
from datetime import datetime
from ruamel.yaml import YAML
from ibx_sdk.nios.gift import Gift
from ibx_sdk.nios.exceptions import WapiRequestException
#
# Global Variables
#
yaml = YAML()
IPADDRS= "/etc/elastiflow/metadata/ipaddrs.yml"
CONFIG = "nios.yml"
GRIDMANAGER = "192.168.2.1"
WAPIVERSION =  "2.12"
USERNAME = "admin"
PASSWORD = "infoblox"
NETWORKVIEW =  "default"

def create_backup(file_path):
    # Get the current date and time
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # Create a backup file name by appending the timestamp to the original file name
    backup_file_path = f"{file_path}.{timestamp}.bak"
    
    # Create the backup by copying the file
    if os.path.isfile(file_path):
        shutil.copy(file_path, backup_file_path)
    else:
        return None
    
    return backup_file_path

def convert_string(s):
    # Convert to lowercase
    lower_s = s.lower()
    # Replace spaces with underscores
    replaced_s = lower_s.replace(" ", "_")
    # Add a period at the beginning
    return replaced_s

def load_variables_from_file(filename):
    if os.path.isfile(filename):
        with open(filename, 'r') as file:
            try:
                config = yaml.load(file)
            except:
                print(f"Error loading YAML file: {filename}")
                return None
        for x in config:
            globals()[x] = config.get(x)
    return None


def update_from_infoblox():

    yaml = YAML()

    with open(IPADDRS, 'r') as file:
        try:
            ipaddrs = yaml.load(file)
        except:
            print(f'\n\nERROR: File: {IPADDRS} does appear to be a valid YML file\n')
            return False
    if ipaddrs is None:
        ipaddrs = {}
    wapi = Gift(grid_mgr=GRIDMANAGER,wapi_ver=WAPIVERSION)
    try:
        wapi.connect(username=USERNAME,password=PASSWORD)
    except:
        print('\n\nCould not connect to Infoblox Grid Manager: Check IP address and user credentials\n')
        print(f'Grid Master: {GRIDMANAGER} \nWAPI Version: {WAPIVERSION} \nUser Name: {USERNAME}\nGird Network View: {NETWORKVIEW}\n')
        print(f'Check Infoblox configuration file: {CONFIG}')
        return False

    my_params = { 'network_view': NETWORKVIEW,
                '_return_fields': 'network,extattrs'
        }
    try:
        response = wapi.get('network',params=my_params)
    except WapiRequestException as e:
        print(f"Error: Infoblox WAPI request error\n{e}")
        return False
    except:
        print('\n\nCould not connect to Infoblox Grid Manager: Check IP address and user credentials')
        return False

    infoblox_data = response.json()
#
# convert json from Infoblox to dict to match ElastiFlow ipaddrs yml format
#
    yaml_dict = {}
    for x in infoblox_data:
        if 'network' in x and 'extattrs' in x:
            cidr = x['network']
            infoblox_extattrs = x['extattrs']
            if len(infoblox_extattrs) == 0:
                continue
            metadict = {}
            netdata = {}
            for y in infoblox_extattrs:
                name = ".ib." + convert_string(y)
                value = infoblox_extattrs[y]['value']
                netdata[name] = value
            
            
            metadict['metadata'] = netdata
            yaml_dict[cidr] = metadict
#
# Update ipaddrs dict with Infoblox Extensible Attribute data
# 
    if len(yaml_dict) > 0:
        for x in yaml_dict:
            if x in ipaddrs:
                ydict = yaml_dict[x]['metadata']
                for y in ydict:
#                    print(f'x: {x} -- y: {y}')
                    if not y in ipaddrs[x]['metadata']:
                        ipaddrs[x]['metadata'][y] = ydict[y]

            else:
                ipaddrs[x]=yaml_dict[x]

    backup_file_path = create_backup(IPADDRS)      
    with open(IPADDRS, 'w') as file:
        yaml.dump(ipaddrs, file)
    print(f"Updated Metadata in {IPADDRS}")
    print(f"Backup created at: {backup_file_path}")
    return True

def main():
    global IPADDRS,CONFIG,GRIDMANAGER,WAPIVERSION,USERNAME,PASSWORD,NETWORKVIEW
    # Create an ArgumentParser object
    helptext = '''This script will use the Infoblox WAPI to pull all extensible attributes
    associated with networks for a specific network view in the Infoblox NIOS IPAM Database.\n\n
    
    Each attribute wil be added to the yml file specified or /etc/elastiflow/metadata/ipaddrs.yml\n\n
    
    Configuration can be passed to the script via a YML file with -c option, default is nios.yml'''

    parser = argparse.ArgumentParser(description=helptext)

    # Add arguments
    parser.add_argument('-f', '--file', type=str, required=False, help='ippaddr.yml with path')
    parser.add_argument('-c','--config', type=str, required=False,  help='Infoblox Configuration File')

    # Parse the arguments
    
    args = parser.parse_args()

    if args.config:
        if not os.path.isfile(args.config):
            print(f'Infoblox config file {args.config} does not exist')
            return
        CONFIG = args.config
    else:
        if not os.path.isfile(CONFIG):
            print(f'Infoblox config file {CONFIG} does not exist')
            return

    load_variables_from_file(CONFIG)

    if args.file:
        if not os.path.isfile(args.file):
            print(f'Metadata file {args.file} does not exist')
            return
        IPADDRS = args.file
        
    
    update_from_infoblox()

if __name__ == '__main__':
    main()