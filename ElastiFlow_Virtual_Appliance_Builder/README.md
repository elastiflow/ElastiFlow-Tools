# ElastiFlow Installation Script
Script to easily install everything needed to PoC ElastiFlow Flowcoll and SNMPColl

## Author
[O.J. Wolanyk]

What this is:
----------------
Script to easily install everything needed to PoC (or run in a small deployment) ElastiFlow Unified Flow Collector and ElastiFlow Unified SNMP Collector

What this script does:
----------------
Downloads, installs, and configures (Elasticsearch, Kibana) or (Opensearch, Opensearch Dashboards), ElastiFlow Unified Flow Collector, and ElastiFlow flow dashboards

Requirements:
----------------
Ubuntu Server 22 or greater

Instructions:
----------------
1) Please review prerequisites [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit#heading=h.e87xs5ntz4yk). Since you are installing everything from scratch (as opposed to importing a virtual appliance) some instructions will not apply).
2) When ready, run the following command in a terminal shell
```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/ElastiFlow_Virtual_Appliance_Builder/install.sh)"
```
3) After installation is complete, please follow the guide [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit?usp=sharing&ouid=106934919212917365947&rtpof=true&sd=true).

Options:
----------------
The following are optional variable assignments that you can make in the script. If you would like to customize the variables in the script, download the shell scripts, edit the key value pairs. as If you are unsure of what these variables mean, please leave them as they are.
```elastiflow_account_id=""
elastiflow_flow_license_key=""
flowcoll_version="7.5.3"

#note: Elastic 8.16.3 is the last version to have free TSDS
elasticsearch_version="8.16.3"
opensearch_version=2.18.0

kibana_version="8.16.13"

flow_dashboards_version="8.14.x"
flow_dashboards_codex_ecs="codex"
osd_flow_dashboards_version="2.14.x"
flowcoll_config_path="/etc/elastiflow/flowcoll.yml"
elastic_username="elastic"
elastic_password2="elastic"
opensearch_username="admin"
opensearch_password2="yourStrongPassword123!"

# vm specs 64 gigs ram, 16 vcpus, 2 TB disk, license for up to 64k FPS, fpus 4 - so there's a 16k FPS limit, 1 week retention
fpus="4"
```
Opensearch:
--------
You will need to switch to the ElastiFlow tenant to see all of the installed ElastiFlow dashboards
