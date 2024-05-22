
ElastiFlow PoC Configurator Version 1.3
================================  

## Author
- [O.J. Wolanyk]

# ElastiFlow PoC configurator
Script to quickly configure ElastiFlow for a trial and MaxMind enrichment


What this is:
----------------
This bash shell script can be run on the ElastiFlow Virtual Appliance 1.4 to automatically configure the flowcoll.conf file to add in trial license information and configure and download MaxMind enrichment.

What this script does:
----------------
Configures trial
  Prompts the user for ElastiFlow account ID and ElastiFlow license key
  Adds this information to flowcoll.conf
  Restarts flowcoll.service and verifies valid changes.
  
Configures MaxMind enrichment
  Prompts the user for MaxMind license key
  Downloads MaxMind databases
  Configures flowcoll.conf for MaxMind enrichment
  Restarts flowcoll.service and verifies valid changes.


Requirements:
----------------
ElastiFlow Virtual Appliance

Instructions:
----------------
1) Copy configure.sh to your home directory on your virtual appliance.
2) sudo chmod +x configure.sh
3) sudo ./configure.sh
