## Author
- [O.J. Wolanyk]

# ElastiFlow_PoC_Installer for ElasticSearch
Script to easily install ElastiFlow for ElasticSearch with all dependencies

What this is:
----------------
Shell scripts for quickly and easily installing on a single Ubuntu virtual machine, the latest versions of everything needed to evaluate ElastiFlow for ElasticSearch. This script can be used by ElastiFlow staff to create personal test environments or even virtual appliances to speed up customer PoCs.

What this script does:
----------------
  Downloads and installs the latest versions of the following:
    ElasticSearch (listening on 9200),
    Kibana (listening on 5601),
    ElastiFlow Unified Flow Collector (listening on 9995),
    ElastiFlow flow dashboards for Kibana
  
  Configures the following:
    Connects Kibana to ElasticSearch,
    Connects ElastiFlow to ElasticSearch,
    Configures services to start on boot

Requirements:
----------------
One Ubuntu Server version 22 or 23, or Debian server version 11 or 12, freshly installed

Instructions:
----------------
1) Copy install.sh to your home directory
2) sudo chmod +x install.sh
3) sudo ./install.sh
4) When completed, access Kibana at http://your_server_ip:5601, (elastic / elastic)
