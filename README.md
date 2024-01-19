# ElastiFlow_for_ElasticSearch_Autoinstaller
Script to easily install ElastiFlow for ElasticSearch with all dependencies

What this is:
----------------
Shell scripts for quickly and easily installing on a single Ubuntu virtual machine, the latest versions of everything needed to evaluate Elastiflow for ElasticSearch. This script can be used by Elastiflow staff to create personal test environments or even virtual appliances to speed up customer PoCs.

What this script does:
----------------
  Downloads and installs the latest versions of the following:
    ElasticSearch (listening on 9200)
    Kibana (listening on 5601)
    Elastiflow Unified Flow Collector (listening on 9995)
    Elastiflow flow dashboards for Kibana
  
  Configures the following:
    Connects Kibana to ElasticSearch
    Connects ElastiFlow to ElasticSearch
    Configures services to start on boot

Requirements:
----------------
One Ubuntu Server

Instructions:
----------------
1) Copy install.sh and install2.sh to your home directory
2) Chmod +x on both files
3) Run sudo ./install.sh
4) When completed, access Kibana at http://your_server_ip:5601, (elastic / elastic)
