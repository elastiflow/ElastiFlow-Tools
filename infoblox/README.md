# Enhance ElastiFlow Metadata with Infoblox Extensible attributes

The provided python script will connect to an Infoblox NIOS Grid Manager and get all the extensible attributes for the network objects in the NIOS IPAM database. It will then add then to a new or existing ElastiFlow NetObserv ipaddrs.yml file to enrich the ElastiFlow flow records with the Infoblox metadata data.

## Table of Contents
- [Project Name](#project-name)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
  - [Configuration](#configuration)
  - [Usage](#usage)
  - [Contact](#contact)

## Features
- Use the Infoblox NIOS WAPI to collect network object attribute data
- Update ElastiFlow NetObserv ipaddrs.yml with Infoblox metadata
  
## Getting Started

### Prerequisites

- Python 3.x
- pip
- Python Libraries:
  - ibx-sdk
  - ruamel.yaml

Reccomend installing python libraries in a virtual environment so you will also need:

- python3.10-venv

### Installation

Create a working directory to run the the script. Since the script requires python libraries to be installed it is suggested to create a python virtual environment to the run the script.

Copy the required files to the current directory

```bash
# Copy the files
wget -o import_nios_ipam.py https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/infoblox/import_nios_ipam.py
wget -o setup_python_venv.sh https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/infoblox/setup_python_venv.sh
wget -o nios.yml https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/infoblox/nios.yml
```


Create Python Virtual Environment and install libraries into the venv. If you chose to use this script it will check for an install python3, pip and python3.10-venv:

```bash
sudo bash setup_python_venv.sh
```

## Configuration

Edit the nios.yml file with your specifc information:

```
IPADDRS: "/etc/elastiflow/metadata/ipaddrs.yml"
GRIDMANAGER: "192.168.1.2"
WAPIVERSION: "2.12"
USERNAME: "admin"
PASSWORD: "infoblox"
NETWORKVIEW: "default"
```

- IPADDRS - the yml file that contains the metadata for ElastiFlow NetObserv flow collector
- GRIDMANAGER - IP address of the Infoblox NIOS Grid Manager or Grid Manager Candidate with API enable
- WAPIVERSION - Version of the Infoblox NIOS WAPI supported by your version of NIOS
- USERNAME - Infoblox NIOS username
- PASSWORD - Infoblox NIOS password for the username provided
- NETWORKVIEW - Name of the Network View in the Infoblox NIOS IPAM Database 

## Usage

Need to activate the Python Virtual Environment. If you wil be updating the /etc/elastiflow/metadata/ipaddrs.yml file directly with this script you will need to run it as "su":

```bash
sudo su
source .venv/bin/activate
```

Execute the python script. This examples assumes you modified the nios.yml file provided and you are updating the production ipaddrs.yml file. You can output the data from Infoblox to any file prior to adding it to your production ipaddrs.yml

```bash

sudo su
python3 import_nios_ipam.py -c nios.yml -f /etc/elastiflow/metadata/ipaddrs.yml
```

To exit the python3 virtual environment run the command: deactivate:

```bash
deactivate
```



## Contact
Post any questions the ElastiFlow community: https://forum.elastiflow.com/c/community/4


