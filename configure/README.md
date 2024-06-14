
ElastiFlow PoC Configuration Script
================================  

## Author
- [O.J. Wolanyk]

# ElastiFlow PoC configurator
Script to streamline getting a PoC ElastiFlow Virtual Appliance up and running.


What this is:
----------------
This bash shell script can be run on the ElastiFlow Virtual Appliance to help configure an IP, add trial credentials, and configure and download MaxMind enrichment.

What this script does:
----------------

Configures a static IP address
  Prompts the user for a static IP, gateway, and DNS servers, and then does a netplan apply

Configures trial
  Prompts the user for an ElastiFlow account ID and ElastiFlow license key
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
2) sudo chmod +x configure
3) sudo ./configure
