
Copy ElastiFlow NetObserv Dashboards across Kibana spaces
================================  

## Authors
- [O.J. Wolanyk, Dexter Turner, Pat Vogelsang]

What this is:
----------------
This script will copy all the ElastiFlow Kibana saved objects that make up the ELastiFlow dashboards from the Kibana default space to a user specified Kibana space.

Requirements:
----------------
- ElastiFlow NetObserv dashboards loaded into the default space in an Elasticsearch with Kibana cluster. 
- Linux host run the script.

Instructions:
----------------
1) Download .env and migrate-ef-kibana-objects.sh files to a linux computer
2) Edit the .env with IP Address, TCP Port and user credentials

Run These commands
```
sudo chmod +x migrate-ef-kibana-objects.sh
sudo ./migrate-ef-kibana-objects.sh <DESTINATION KIBANA SPACE NAME>
```
