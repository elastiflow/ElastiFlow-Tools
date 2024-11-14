#!/bin/bash

# Check if a pcap file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <pcap_file>"
    exit 1
fi

# Define the pcap file
pcap_file="$1"

# Check if tshark is installed, and prompt to install if missing
if ! command -v tshark &> /dev/null; then
    echo "tshark is not installed. Would you like to install it? (y/n)"
    read -r install_choice
    if [[ "$install_choice" != "y" ]]; then
        echo "tshark is required to run this script. Exiting."
        exit 1
    fi

    # Install tshark based on the available package manager
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y tshark
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y tshark
    elif command -v yum &> /dev/null; then
        sudo yum install -y tshark
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y tshark
    else
        echo "Unsupported package manager. Please install tshark manually."
        exit 1
    fi
fi

# Run the command and calculate total flow records, time difference, and FPS
tshark -r "$pcap_file" -Y 'cflow' -T fields -e frame.time_epoch -e cflow.count | \
awk 'NR == 1 {start = $1} {sum += $2; end = $1} END {time_diff = end - start; fps = (time_diff > 0) ? sum / time_diff : 0; print "Total flow records:", sum; print "Time between first and last record (seconds):", time_diff; print "Flow records per second (FPS):", fps}'
