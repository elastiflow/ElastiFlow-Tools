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
Clean, unused Ubuntu Server 22 or greater

Instructions:
----------------
1) Please review prerequisites [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit#heading=h.e87xs5ntz4yk). Since you are installing everything from scratch (as opposed to importing a virtual appliance) some instructions will not apply.
2) When ready, run the following command in a terminal shell
```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/ElastiFlow_Virtual_Appliance_Builder/install.sh)"
```
3) After installation is complete, please follow the guide [here](https://docs.google.com/document/d/18XOxnAdxAW5bcqRRGEEKayJf_ViwYRAG/edit?usp=sharing&ouid=106934919212917365947&rtpof=true&sd=true).

Options:
----------------

To run this script unattended (Elasticsearch will be the default data platform in this case) you can do this:
```
wget -qO install.sh https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/ElastiFlow_Virtual_Appliance_Builder/install.sh
chmod +x install.sh
sudo ./install.sh --unattended
```

The following are optional variable assignments that you can make in the script. If you would like to customize the variables in the script, download the shell scripts, and edit the key value pairs. If you are unsure of what these variables mean, please leave them as they are.

```
### ElastiFlow parameters
flowcoll_config_path="/etc/elastiflow/flowcoll.yml"
ef_license_key=""
ef_account_id=""
frps="16000"

### Elasticsearch parameters
# Note: Elasticsearch 8.16.4 is the last version to have free TSDS
elasticsearch_version="8.16.4"
elastic_tsds="true"
kibana_version="8.16.4"
elastic_username="elastic"
elastic_password="elastic"
flow_dashboards_version="8.14.x"
# If you are using CODEX schema, this should be set to "codex". Otherwise set to "ecs"
flow_dashboards_codex_ecs="codex"
# If you are using CODEX schema, this should be set to "false". Otherwise, set to "true", for ECS.
ecs_enable="false"

### OpenSearch parameters
opensearch_version=2.19.0
opensearch_username="admin"
opensearch_password2="yourStrongPassword123!"
osd_flow_dashboards_version="2.14.x"
```

```
Opensearch:
--------
You will need to switch to the ElastiFlow tenant to see all of the installed ElastiFlow dashboards
