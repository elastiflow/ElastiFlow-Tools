#!/bin/bash

# Function to install tcpreplay and tcprewrite on Ubuntu
install_tools() {
    echo "tcpreplay and tcprewrite are not installed. Would you like to install them? (y/n)"
    read -p "Install tools? (default: y): " install_choice
    install_choice=${install_choice:-y}

    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        echo "Installing tcpreplay and tcprewrite..."
        sudo apt-get update
        sudo apt-get install -y tcpreplay
        sudo apt-get install -y tcprewrite
        echo "Installation complete."
    else
        echo "Installation aborted. Exiting."
        exit 1
    fi
}

# Check for tcprewrite and tcpreplay
if ! command -v tcprewrite &> /dev/null || ! command -v tcpreplay &> /dev/null; then
    # Check if the OS is Ubuntu
    if [[ -f /etc/os-release && $(grep -w 'ID=ubuntu' /etc/os-release) ]]; then
        install_tools
    else
        echo "Error: tcprewrite and/or tcpreplay are not installed. Please install them to proceed."
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

# Prompt for destination IP
read -p "Enter destination IP (default: 192.168.2.80): " dest_ip
dest_ip=${dest_ip:-192.168.2.80}

# Prompt for destination port
read -p "Enter destination port (default: 9995): " dest_port
dest_port=${dest_port:-9995}

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

# Prompt for topspeed option
read -p "Use topspeed for replay? (y/n, default: n): " topspeed
topspeed=${topspeed:-n}

# Set topspeed flag for tcpreplay
if [[ "$topspeed" =~ ^[Yy]$ ]]; then
    topspeed_flag="--pps=1000000"  # Set an arbitrary high value for topspeed
else
    topspeed_flag=""
fi

# If the input file is a zip file, unzip it first
if [[ "$input_file" == *.zip ]]; then
    dir_name=$(dirname "$input_file")  # Get the directory of the zip file
    unzip -o "$input_file" -d temp_dir
    input_file=$(ls temp_dir/*.pcap)  # Get the first pcap file in the directory
    if [[ -z "$input_file" ]]; then
        echo "Error: No pcap file found in the zip."
        exit 1
    fi
else
    dir_name=$(dirname "$input_file")  # Use the directory of the original pcap file
fi

# Get the base name and define the modified file path
base_name=$(basename "$input_file" .pcap)
modified_file="$dir_name/${base_name}_modified.pcap"

# Modify destination IP and port using tcprewrite
tcprewrite --infile="$input_file" --outfile="$modified_file" --dstipmap=0.0.0.0/0:"$dest_ip" --portmap=0:"$dest_port"

# Summary of changes
echo "Summary of Changes:"
echo "-------------------"
echo "Changed all destination IPs to: $dest_ip"
echo "Changed all destination ports to: $dest_port"
echo "Using interface: $interface"
echo "Modified file saved as: $modified_file"
echo "-------------------"

# Replay the modified packets using tcpreplay
tcpreplay $topspeed_flag --intf1="$interface" "$modified_file"

# Clean up temporary files if a zip was used
if [[ "$1" == *.zip ]]; then
    rm -rf temp_dir
fi

echo "Replay completed."
