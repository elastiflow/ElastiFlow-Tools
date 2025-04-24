import yaml
import ipaddress
import random

def generate_netif_yaml(filename="netif.yml", num_ips=10000, entries_per_ip=100):
    base_network = ipaddress.IPv4Network("10.10.0.0/16")
    if_names = [f"Port-Channel{100 + i}" for i in range(entries_per_ip)]  # Ensure enough unique names per IP

    base_entry = {
        "ifAlias": "Peer_link_PortChannel",
        "ifSpeed": 80000,
        "ifType": 167,
    }
    
    netif_data = {}
    ip_list = list(base_network.hosts())[:num_ips]  # Get the first num_ips usable addresses

    for i in range(num_ips):
        ip_address = str(ip_list[i])
        shuffled_if_names = random.sample(if_names, len(if_names))  # Shuffle for uniqueness within IP

        netif_data[ip_address] = {
            17000 + j: {
                **base_entry,
                "ifName": shuffled_if_names[j],  # Assign unique ifName per index within this IP
                "ifDescr": shuffled_if_names[j]  # Sync ifDescr with ifName
            }
            for j in range(entries_per_ip)
        }
    
    with open(filename, "w") as file:
        yaml.dump(netif_data, file, default_flow_style=False, default_style=None)
    
    print(f"Generated {filename} with {num_ips} IP addresses and {entries_per_ip} unique entries per IP.")

if __name__ == "__main__":
    generate_netif_yaml()