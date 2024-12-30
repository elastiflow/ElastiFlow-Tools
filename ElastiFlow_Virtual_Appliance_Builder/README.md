# ElastiFlow Installation Script
Script to easily install everything needed to PoC ElastiFlow Flowcoll and SNMPColl

## Author
[O.J. Wolanyk]

What this is:
----------------
Script to easily install everything needed to PoC (or run in a small deployment) ElastiFlow Unified Flow Collector and ElastiFlow Unified SNMP Collector

What this script does:
----------------
Downloads, installs, and configures Elasticsearch, Kibana, ElastiFlow Unified Flow Collector, and ElastiFlow flow dashboards

Requirements:
----------------
Ubuntu Server 22 or greater

Instructions:
----------------
1) Please review prerequisites [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit#heading=h.e87xs5ntz4yk). Since you are installing everything from scratch (as opposed to importing a virtual appliance) some instructions will not apply).
2) When ready, run the following command in a terminal shell
```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/elasticsearch/install.sh)"
```
3) After installation is complete, please follow the guide [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit?usp=sharing&ouid=106934919212917365947&rtpof=true&sd=true).

Options:
----------------
Options:
The following are optional variable assignments that you can make in the script. If you are unsure of what these variables mean, please leave them as they are.
```elastiflow_account_id=""
elastiflow_flow_license_key=""
flowcoll_version="7.5.3"

#note: Elastic 8.16.1 is the last version to have free TSDS
elasticsearch_version="8.16.1"

kibana_version="8.16.1"

flow_dashboards_version="8.14.x"
flow_dashboards_codex_ecs="codex"
flowcoll_config_path="/etc/elastiflow/flowcoll.yml"
elastic_username="elastic"
elastic_password2="elastic"

# vm specs 64 gigs ram, 16 vcpus, 2 TB disk, license for up to 64k FPS, fpus 4 - so there's a 16k FPS limit, 1 week retention
fpus="4"
```
