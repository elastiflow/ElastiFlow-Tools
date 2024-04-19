#!/bin/bash

echo "Enter the path to the pcap file:"
read file_path

if [ ! -f "$file_path" ]; then
    echo "File does not exist."
    exit 1
fi

# Extract flows: source IP, destination IP, source and destination ports, and protocol
flows=$(tcpdump -r "$file_path" -nn -t 'tcp or udp' -q \
        | awk '{print $1,$3,$5}' \
        | sed 's/.$//' \
        | sort -u)

# Count unique flows
num_flows=$(echo "$flows" | wc -l)

# Calculate the capture duration
start_time=$(tcpdump -r "$file_path" -nn -tt | head -1 | awk '{print $1}')
end_time=$(tcpdump -r "$file_path" -nn -tt | tail -1 | awk '{print $1}')
duration=$(echo "$end_time - $start_time" | bc -l)

# Compute flows per second
if (( $(echo "$duration > 0" | bc -l) )); then
    flows_per_second=$(echo "$num_flows / $duration" | bc -l)
else
    flows_per_second=0
fi

echo "Total number of flows: $num_flows"
echo "Duration of capture: $duration seconds"
echo "Flows per second: $flows_per_second"
