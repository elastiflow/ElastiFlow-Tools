import requests
import yaml

# API token and URL configuration
API_TOKEN = '9efdcab9667d7314eb73157c839cd6c970ab5718'  # Replace with your actual API token
NETBOX_API_URL = 'http://192.168.1.6:8000/api/dcim/devices/'
SITES_API_URL = 'http://192.168.1.6:8000/api/dcim/sites/'

# Headers for the API request
headers = {
    'Authorization': f'Token {API_TOKEN}',
    'Accept': 'application/json'
}

# Function to get device details from NetBox API
def get_device_details():
    response = requests.get(NETBOX_API_URL, headers=headers)
    response.raise_for_status()  # Raise an error for failed requests
    return response.json()['results']

# Function to get site details from NetBox API
def get_site_details(site_name):
    response = requests.get(SITES_API_URL, headers=headers)
    response.raise_for_status()
    sites = response.json()['results']
    
    # Match the site name to find the correct site details
    for site in sites:
        if site['name'] == site_name:
            return site
    return None

# Function to safely parse the physical address
def parse_address(physical_address):
    if not physical_address or ',' not in physical_address:
        return None, None

    try:
        # Assuming the format: "Street Address, City, State, Zip, Country Code"
        parts = physical_address.split(',')
        city = parts[1].strip() if len(parts) > 1 else None  # Extract city
        country_code = parts[-1].strip() if len(parts) > 1 else None  # Extract country code
        return city, country_code
    except IndexError:
        return None, None

# Function to filter out None or 'N/A' values from metadata
def filter_metadata(metadata):
    return {k: v for k, v in metadata.items() if v not in (None, 'N/A')}

# Function to extract the relevant fields and format them into YAML
def format_to_yaml(devices):
    yaml_data = {}

    for device in devices:
        primary_ip4 = device.get('primary_ip4', {}).get('address', None)
        site_name = device.get('site', {}).get('name', None)
        manufacturer_name = device.get('device_type', {}).get('manufacturer', {}).get('name', None)
        role_name = device.get('role', {}).get('name', None)
        latitude = device.get('latitude', None)
        longitude = device.get('longitude', None)

        # Perform second API call to get geographical information from site details
        site_details = get_site_details(site_name) if site_name else None
        if site_details:
            physical_address = site_details.get('physical_address', None)
            time_zone = site_details.get('time_zone', None)
            # Extract city, country code from the physical address
            city_name, country_code = parse_address(physical_address)
        else:
            time_zone = None
            city_name = None
            country_code = None

        # If latitude and longitude are available, format them as "lat,lon"
        geo_coords = f"{latitude},{longitude}" if latitude is not None and longitude is not None else None

        # Constructing the metadata, filtering out 'N/A' or None values
        metadata = {
            f'company.site.name': site_name,
            'device.type.name': manufacturer_name,
            '.geo.loc.coord': geo_coords,
            '.geo.city.name': city_name,
            '.geo.country.code': country_code,
            '.geo.country.name': None,  # You can remove or customize if country names are not needed
            '.geo.tz.name': time_zone
        }

        # Filter out entries with None or 'N/A' values
        filtered_metadata = filter_metadata(metadata)

        # Only add devices that have valid primary IP and metadata
        if primary_ip4 and filtered_metadata:
            yaml_data[primary_ip4] = {
                'tags': [role_name] if role_name else [],
                'metadata': filtered_metadata
            }

    # Return the formatted YAML string
    return yaml.dump(yaml_data, sort_keys=False)

# Main execution
if __name__ == '__main__':
    try:
        devices = get_device_details()
        yaml_output = format_to_yaml(devices)

        # Save to a file
        with open('netbox_devices.yml', 'w') as f:
            f.write(yaml_output)

        print('YAML file generated successfully!')
    except Exception as e:
        print(f"Error: {e}")
