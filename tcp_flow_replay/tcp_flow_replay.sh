#!/bin/bash

# Function to install tcpreplay, tcprewrite, and tcpdump on Ubuntu
install_tools() {
    echo "tcpreplay, tcprewrite, and tcpdump are not installed. Would you like to install them? (y/n)"
    read -p "Install tools? (default: y): " install_choice
    install_choice=${install_choice:-y}

    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        echo "Installing tcpreplay, tcprewrite, and tcpdump..."
        sudo apt-get update
        sudo apt-get install -y tcpreplay tcpdump
        echo "Installation complete."
    else
        echo "Installation aborted. Exiting."
        exit 1
    fi
}

# Check for tcprewrite, tcpreplay, and tcpdump
if ! command -v tcprewrite &> /dev/null || ! command -v tcpreplay &> /dev/null || ! command -v tcpdump &> /dev/null; then
    # Check if the OS is Ubuntu
    if [[ -f /etc/os-release && $(grep -w 'ID=ubuntu' /etc/os-release) ]]; then
        install_tools
    else
        echo "Error: tcprewrite, tcpreplay, and/or tcpdump are not installed. Please install them to proceed."
        exit 1
    fi
fi

# Get the input file (pcap or zip)
if [[ -z "$1" ]]; then
    echo "Usage: $0 <input.pcap|input.zip>"
    exit 1
fi

input_file="$1"

# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' does not exist."
    exit 1
fi

# Check for SLL headers and convert to Ethernet if necessary
base_name=$(basename "$input_file" .pcap)
temp_file="${base_name}_temp.pcap"

echo "Checking for SLL headers and converting to Ethernet if necessary..."
tcpdump -r "$input_file" -w "$temp_file" -s 0 2>&1 | grep -q 'cooked'
if [[ $? -eq 0 ]]; then
    echo "SLL headers detected and converted to Ethernet format."
    mv "$temp_file" "$input_file"  # Replace original file with converted file
else
    rm "$temp_file"  # Clean up temp file if no conversion was needed
    echo "No SLL headers detected, or already in Ethernet format."
fi

# Prompt for new destination MAC address
read -p "Enter new destination MAC address (e.g., 00:1a:2b:3c:4d:5e): " new_dest_mac
if [[ -z "$new_dest_mac" ]]; then
    echo "No destination MAC address provided, exiting."
    exit 1
fi

# Prompt for destination IP
read -p "Enter destination IP (default: 192.168.2.80): " dest_ip
dest_ip=${dest_ip:-192.168.2.80}

# List available network interfaces and prompt for one
echo "Available network interfaces:"
interfaces=($(ip -o -f inet addr show | awk '{print $2}'))

for i in "${!interfaces[@]}"; do
    echo "$i: ${interfaces[$i]}"
done

read -p "Enter the number corresponding to the network interface to use for replay (default: 0 for ${interfaces[0]}): " interface_index
interface_index=${interface_index:-0}

# Set default to eth0 if input is out of range or no selection is made
if [[ -z "${interfaces[$interface_index]}" ]]; then
    interface="eth0"
else
    interface="${interfaces[$interface_index]}"
fi

# Ensure eth0 is used if it exists and was not specified
if [[ "$interface" != "eth0" && " ${interfaces[@]} " =~ " eth0 " ]]; then
    interface="eth0"
fi

# Get the MAC address of the chosen network interface
source_mac=$(cat /sys/class/net/$interface/address)

echo "Source MAC of selected interface ($interface) is $source_mac"

# Get the directory name for the input file
dir_name=$(dirname "$input_file")

# Modify destination IP and MAC address using tcprewrite
modified_file="${dir_name}/${base_name}_modified.pcap"
tcprewrite --infile="$input_file" --outfile="$modified_file" --dstipmap=0.0.0.0/0:"$dest_ip" --enet-dmac="$new_dest_mac" --enet-smac="$source_mac"

# Summary of changes
echo "Summary of Changes:"
echo "-------------------"
echo "Changed all destination IPs to: $dest_ip"
echo "Changed destination MAC to: $new_dest_mac"
echo "Set source MAC to interface MAC: $source_mac"
echo "Using interface: $interface"
echo "Modified file saved as: $modified_file"
echo "-------------------"

# Replay the modified packets using tcpreplay
tcpreplay --intf1="$interface" "$modified_file"

echo "Replay completed."
