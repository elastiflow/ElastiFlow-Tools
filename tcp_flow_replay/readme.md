## Author
- [O.J. Wolanyk]

What this is:
----------------
A shell script to easily replay packets obtained from others.

What this script does:
----------------
This script accepts a pcap or zipped pcap file, prompts the user for an destination mac, destination IP address, and destination port, and then applies these values (along with the chosen exporting interface's MAC adress) using tcprewrite. Finally, it replays the modified pcap using tpreplay.

Requirements:
----------------

Instructions:
----------------
```
./tcp_flow_replay.sh your_pcap.pcap
```
