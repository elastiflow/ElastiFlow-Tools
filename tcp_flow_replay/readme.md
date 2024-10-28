## Author
- [O.J. Wolanyk]

# ElastiFlow Installation Script
Script to easily replay netflow pcaps to the ip and port of your choice.

What this is:
----------------

What this script does:
----------------
This script accepts a pcap or zipped pcap file, prompts the user for a destination IP address and port, uses tcprewrite to make the changes to the pcap and then replays the pcaps with tcpreplay.

Requirements:
----------------

Instructions:
----------------
```
./tcp_flow_replay.sh your_pcap.pcap
```
