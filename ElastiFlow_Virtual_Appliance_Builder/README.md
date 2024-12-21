# ElastiFlow Installation Script
Script to easily install everything needed to PoC ElastiFlow Flowcoll and SNMPColl

## Author
[O.J. Wolanyk]

What this is:
----------------
Script to easily install everything needed to PoC (or run in a small deployment) ElastiFlow Unified Flow Collector and ElastiFlow Unified SNMP Collector

What this script does:
----------------
Downloads, installs, and configures Elasticsearch, Kibana, and ElastiFlow Unified Flow Collector and ElastiFlow dashboards

Requirements:
----------------
Ubuntu Server 22 or greater

Instructions:
----------------
1) Please review prerequisites [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit?usp=sharing&ouid=106934919212917365947&rtpof=true&sd=true). Since you are installing everything from scratch (as opposed to importing a virtual appliance) some instructions will not apply).
2) When ready, run the following command in a terminal shell
```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/elasticsearch/install.sh)"
```
3) After installation is complete, please follow the guide [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit?usp=sharing&ouid=106934919212917365947&rtpof=true&sd=true).
