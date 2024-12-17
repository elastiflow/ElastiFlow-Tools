#!/bin/bash

# Function to check if script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;33mWarning: This script is not running as root.\033[0m"
        echo "Certain operations might require root permissions."
        read -p "Do you want to restart this script as root? (y/n): " choice

        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo "Restarting script with root privileges..."
            exec sudo bash "$0" "$@"
        else
            echo "Proceeding without root permissions..."
        fi
    fi
}

# Function to detect and install required tools for Ubuntu and RedHat-based systems
install_tools() {
    echo "tcpreplay, tcprewrite, and tcpdump are not installed. Would you like to install them? (y/n)"
    read -p "Install tools? (y/n): " install_choice

    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        echo "Installing tcpreplay, tcprewrite, and tcpdump..."
        if [[ -f /etc/redhat-release ]]; then
            sudo yum install -y epel-release
            sudo yum install -y tcpreplay tcpdump
        elif [[ -f /etc/os-release && $(grep -w 'ID=ubuntu' /etc/os-release) ]]; then
            sudo apt-get update
            sudo apt-get install -y tcpreplay tcpdump
        else
            echo "Unsupported distribution. Install the tools manually."
            exit 1
        fi
        echo "Installation complete."
    else
        echo "Installation aborted. Exiting."
        exit 1
    fi
}

# Run root check
check_root "$@"

# Check for tcprewrite, tcpreplay, and tcpdump
if ! command -v tcprewrite &> /dev/null || ! command -v tcpreplay &> /dev/null || ! command -v tcpdump &> /dev/null; then
    install_tools
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
read -p "Enter destination IP: " dest_ip
if [[ -z "$dest_ip" ]]; then
    echo "No destination IP provided, exiting."
    exit 1
fi

# List available network interfaces and prompt for one
echo "Available network interfaces:"
interfaces=($(ip -o -f inet addr show | awk '{print $2}'))

for i in "${!interfaces[@]}"; do
    echo "$i: ${interfaces[$i]}"
done

read -p "Enter the number corresponding to the network interface to use for replay: " interface_index
if [[ -z "${interfaces[$interface_index]}" ]]; then
    echo "Invalid selection, exiting."
    exit 1
else
    interface="${interfaces[$interface_index]}"
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

# Function to prompt for replay options
prompt_replay_options() {
    echo "Replay Options:"
    echo "1. Replay at packets per second (PPS) rate"
    echo "2. Replay at top speed"
    echo "3. Replay as is (default timing)"
    echo "4. Quit"
    read -p "Choose an option (1/2/3/4): " replay_option

    if [[ $replay_option -eq 4 ]]; then
        echo "Exiting script."
        exit 0
    fi

    if [[ $replay_option -eq 1 ]]; then
        read -p "Enter packets per second (PPS): " pps_rate
        if [[ -z "$pps_rate" ]]; then
            echo "No PPS rate provided. Exiting."
            exit 1
        fi
    fi
}

# Function to replay packets
do_replay() {
    case $replay_option in
        1)
            echo "Replaying with command: tcpreplay --intf1="$interface" --pps="$pps_rate" "$modified_file""
            tcpreplay --intf1="$interface" --pps="$pps_rate" "$modified_file"
            ;;
        2)
            echo "Replaying with command: tcpreplay --intf1="$interface" --topspeed "$modified_file""
            tcpreplay --intf1="$interface" --topspeed "$modified_file"
            ;;
        3)
            echo "Replaying with command: tcpreplay --intf1="$interface" "$modified_file""
            echo "Replaying with default timing..."
            tcpreplay --intf1="$interface" "$modified_file"
            ;;
    esac
    echo "Replay completed."
}

# Initial replay prompt
prompt_replay_options

while true; do
    do_replay
    echo "Options:"
    echo "1. Replay again with new speed options"
    echo "2. Quit"
    read -p "Choose an option (1/2): " replay_again
    if [[ "$replay_again" == "2" ]]; then
        echo "Exiting replay."
        break
    elif [[ "$replay_again" == "1" ]]; then
        prompt_replay_options
    else
        echo "Invalid option, exiting."
        break
    fi
    echo "Restarting replay..."
done

echo "Script execution finished."
