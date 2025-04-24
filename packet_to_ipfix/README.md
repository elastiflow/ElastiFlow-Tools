# IPFIX Exporter in Python

This tool exports IPFIX (NetFlow v10) flow records based on live network traffic captured from a specified interface using Scapy.

---

## Features

- Live packet capture with Scapy
- Flow aggregation by 5-tuple + protocol
- Export of IPFIX templates and data records
- Compatible with ElastiFlow and other IPFIX collectors
- Configurable via `config.json`

---

## Requirements

### For Ubuntu/Debian:

Install Python and Scapy using the system package manager:

```bash
sudo apt update
sudo apt install -y python3 python3-scapy

# IPFIX Exporter

This is a lightweight Python IPFIX (NetFlow v10) exporter that sniffs packets from a network interface and sends IPFIX flow records to a collector like ElastiFlow.

## Features
- Live capture of TCP/UDP flows using Scapy
- Aggregation of flows by source/destination IP and ports
- Export of IPFIX templates and flow records
- Includes packet/byte counters and TCP flags
- Periodically resends templates to maintain compatibility with collectors

---

## Configuration
Create a `config.json` file in the same directory:

```json
{
  "COLLECTOR_IP": "10.101.2.148",
  "COLLECTOR_PORT": 2055,
  "TEMPLATE_ID": 256,
  "DOMAIN_ID": 1234,
  "INTERFACE": "eth0",
  "ACTIVE_TIMEOUT": 60,
  "INACTIVE_TIMEOUT": 30,
  "EXPORTER_PORT": 4739,
  "TEMPLATE_INTERVAL": 300
}
```

---

## Linux Installation
### 1. Install dependencies
```bash
sudo apt update
sudo apt install -y python3 python3-scapy
```

### 2. Run the exporter
```bash
sudo python3 packet_to_ipfix.py
```

---

## macOS Installation
### 1. Install Python and set up a virtual environment
```bash
brew install python
python3 -m venv netflow-env
source netflow-env/bin/activate
pip install scapy
```

### 2. Run the exporter with root privileges
```bash
sudo netflow-env/bin/python packet_to_ipfix.py
```

### 3. Notes for macOS
- macOS can randomize UDP source ports; this script uses a fixed `EXPORTER_PORT` for stability.
- Ensure the `INTERFACE` matches your active interface (e.g. `en0`, `en1`); use `ifconfig` to list interfaces.

---

## 🛠️ Troubleshooting
- Ensure the collector receives both the **template** and **data** messages from the same source port.
- Use Wireshark/tcpdump to confirm IPFIX packets are being sent from your system.
- If the collector logs `template not yet received`, increase the frequency of template refresh or verify source ports match.

---

## Compatible Collectors
- [ElastiFlow](https://github.com/elastiflow/elastiflow)

---

## Author
Built by @eric with clarity, compatibility, and cross-platform support in mind.

