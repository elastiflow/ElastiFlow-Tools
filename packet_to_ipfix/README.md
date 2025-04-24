# IPFIX Exporter in Python

This tool exports IPFIX (NetFlow v10) flow records based on live network traffic captured from a specified interface using Scapy.

---

## ✅ Features

- Live packet capture with Scapy
- Flow aggregation by 5-tuple + protocol
- Export of IPFIX templates and data records
- Compatible with ElastiFlow and other IPFIX collectors
- Configurable via `config.json`

---

## 📦 Requirements

### 🐧 For Ubuntu/Debian:

Install Python and Scapy using the system package manager:

```bash
sudo apt update
sudo apt install -y python3 python3-scapy

