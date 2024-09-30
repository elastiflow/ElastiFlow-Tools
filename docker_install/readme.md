
ElastiFlow Docker Deployment Tool
================================  

## Author
[O.J. Wolanyk]

### Purpose:
To easily install ElasticSearch, Kibana, and ElastiFlow with Docker Compose. Tested with Elastic / Kibana 8.15.1 and ElastiFlow 7.2.2.

### Prerequisites:
- Internet connected, clean Ubuntu 22 (or greater) Linux server with admin access.

- 16 GB of RAM, 4 CPU cores, and 500 GB of disk space. This will allow you to store roughly 1 month of flow data at 500 FPS.

- Docker. If you do not have Docker, you can install it with the following one liner:
```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install_docker.sh)"
```

### Instructions:

#### 1) Add the following recommended kernel tuning parameters to /etc/sysctl.conf

```
vm.max_map_count=262144
net.core.netdev_max_backlog=4096
net.core.rmem_default=262144
net.core.rmem_max=67108864
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_mem=2097152 4194304 8388608
```
To activate the settings, run `sudo sysctl -p`

You could instead use the following one liner to do everything:

```
echo -e "\n# Memory mapping limits for Elasticsearch\nvm.max_map_count=262144\n# Network settings for high performance\nnet.core.netdev_max_backlog=4096\nnet.core.rmem_default=262144\nnet.core.rmem_max=67108864\nnet.ipv4.udp_rmem_min=131072\nnet.ipv4.udp_mem=2097152 4194304 8388608" | sudo tee -a /etc/sysctl.conf > /dev/null && sudo sysctl -p
```

##### Explanation of parameters:

`vm.max_map_count=262144`: Sets the max memory map areas per process, important for Elasticsearch to handle memory-mapped files. Default is often lower, so 262144 is needed for smooth operation.

`net.core.netdev_max_backlog=4096`: Defines the max queued packets at the network interface. A higher value (4096) helps systems with high traffic prevent packet drops.

`net.core.rmem_default=262144`: Sets the default socket receive buffer size (262144 bytes). Useful for applications like Elasticsearch that handle large amounts of data.

`net.core.rmem_max=67108864`: Defines the max socket receive buffer size (up to 64 MB) for handling high-throughput applications.

`net.ipv4.udp_rmem_min=131072`: Sets the minimum UDP socket receive buffer (131072 bytes), ensuring adequate space for UDP traffic without dropping packets.

`net.ipv4.udp_mem=2097152 4194304 8388608`: Defines UDP memory limits (in pages). 2 GB slows socket allocation, 4 GB starts dropping packets, and 8 GB is the max allowed. Helps manage high UDP traffic.

#### 2) Disable swapping

High performance data platforms like Elastic don't like to swap to disk.

1) First, view your current swap configuration with `swapon --show`. If swap is active, you'll see the details of the swap partitions or files. Turn off swapping with `sudo swapoff -a`

2) If there is a swap partition, in the /etc/fstab file, look for the line that defines the swap partition or file and comment it out.  It usually looks something like this:
`/swapfile none swap sw 0 0`. If there is a swap file, then delete it with, `sudo rm /swap.img` replacing `swapfile.img` with the name of your swap file.

3) Verify swap is off with `swapon --show`

#### 3) Download Docker Compose files
Create a new directory on your server and download `elasticsearch_kibana_compose.yml`, `elastiflow_compose.yml`, and `.env` from [here](https://github.com/elastiflow/ElastiFlow-Tools/edit/main/docker_install)

Or run the following in a terminal session:

```
sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env" && sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml" && sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_compose.yml" && sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/readme.md"
```

#### 4) Download required ElastiFlow support files
Download ElastiFlow from [here.](https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb) 

Extract the contents of `/etc/elastiflow/` in the archive to `/etc/elastiflow/`.

You can instead use a one liner to do everything:
```
sudo wget -O flow-collector_7.2.2_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb && sudo mkdir -p elastiflow_extracted && sudo dpkg-deb -x flow-collector_7.2.2_linux_amd64.deb elastiflow_extracted && sudo mkdir -p /etc/elastiflow && sudo cp -r elastiflow_extracted/etc/elastiflow/. /etc/elastiflow
```
#### OPTIONAL: Geo and ASN Enrichment

If you would like to enable geo IP and ASN enrichment, please do the following:

1) Sign up for [Geolite2](https://www.maxmind.com/en/geolite2/signup) database access.
2) Download gzip files (GeoLite2 ASN and GeoLite2 City)
3) Extract their contents to `/etc/elastiflow/maxmind/`
4) Enable Geo and ASN enrichment in `elastiflow_compose.yml`
```
EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_GEOIP_ENABLE: 'true'
EF_PROCESSOR_ENRICH_IPADDR_MAXMIND_ASN_ENABLE: 'true'
```
To automate steps 2 and 3, you could run the following commands on your server:
Be sure to replace `YOUR_LICENSE_KEY` with your GeoLite2 license key.
```
sudo wget -O ./GeoLite2-ASN.tar.gz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=YOUR_LICENSE_KEY&suffix=tar.gz"
sudo wget -O ./GeoLite2-City.tar.gz  "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz"
sudo tar -xvzf GeoLite2-ASN.tar.gz --strip-components 1 -C /etc/elastiflow/maxmind/
sudo tar -xvzf GeoLite2-City.tar.gz  --strip-components 1 -C /etc/elastiflow/maxmind/
```


#### 5) Deploy 

From the directory where you downloaded the yml and .env files, 
```
sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d
```
#### 6) Log in to Kibana 

After a few minutes, browse to `http://IP_of_your_host:5601`.

Username: `elastic` 
Password: `elastic`

#### 7) Install ElastiFlow dashboards:

1) Download this [dashboards file](https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson) to your local machine.

2) Log in to Kibana

3) If given the choice, click "Explore on my own"

4) Do a global search (at the top) for "Saved Objects". Select it 

5) Browse for and upload the ndjson file you downloaded. Choose "import" and "overwrite".

#### 8) Send Netflow
Send Netflow to IP_of_your_host 9995. Refer to your hardware vendor for documentation on how to configure netflow export.

#### 9) Visualize Netflow
In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it. It may be a few minutes for flow records to populate as the system waits for flow templates to arrive.

#### 10) Update Credentials
coming soon

## Notes

- If you need to make any ElastiFlow configuration changes such as turning options on and off, adding your license information, etc, go ahead and edit the elastiflow_compose.yml and then do a 
```
sudo docker compose -f elastiflow_compose.yml down && sudo docker compose -f elastiflow_compose.yml up -d
```
- After making configuration changes, if ElastiFlow starts and then stops or fails to stay running, check the logs by doing
```
sudo docker logs flow-collector -f
```
- If your server is has a different amount of RAM than 16GB, please view the .env file for guidance on the values for the following keys:

`JVM_HEAP_SIZE`

`MEM_LIMIT_ELASTIC`

`MEM_LIMIT_KIBANA`

- If you would like to request a free basic license go [here](https://www.elastiflow.com/basic-license). You can also request a 30 day premium license which unlocks broader device support, much higher flow rates, and [NetIntel enrichments](https://www.elastiflow.com/blog/posts/elastiflow-launches-netintel-to-boost-enterprise-security-against-internal), click [here](https://www.elastiflow.com/get-started).
 
- Questions?
  [Documentation](https://docs.elastiflow.com) | [Community Forum](https://forum.elastiflow.com) | [Slack](https://elastiflowcommunity.slack.com) 
- Code in this folder may contain code from [Elastic's Github Repo.](https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker)

