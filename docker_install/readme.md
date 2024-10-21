
ElastiFlow NetObserv Flow + Elastic Full Stack Deployment with Docker
================================  

## Author
[O.J. Wolanyk]

### Purpose:
To easily install ElasticSearch, Kibana, and ElastiFlow NetObserv Flow with Docker Compose. Tested with Elastic / Kibana 8.15.1 and ElastiFlow NetObserv Flow 7.2.2.

### Prerequisites:
- Internet connected, clean Ubuntu 22 (or greater) Linux server with admin access

- Ubuntu VM should have access to 16 GB of RAM, 8 CPU cores, and 500 GB of disk space. This will allow you to store roughly 1 month of flow data at 500 FPS
  
- Good copying and pasting skills

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
Create a new directory on your server and download `elasticsearch_kibana_compose.yml`, `elastiflow_flow_compose.yml`, and `.env` from [here](https://github.com/elastiflow/ElastiFlow-Tools/edit/main/docker_install)

Or run the following in a terminal session:

```
sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env" && sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml" && sudo wget "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_flow_compose.yml"
```

#### 4) Download required ElastiFlow NetObserv Flow support files
Download ElastiFlow from [here.](https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb) 

Extract the contents of `/etc/elastiflow/` in the archive to `/etc/elastiflow/` on your ElastiFlow NetObserv Flow server.

You can instead use a one liner to do everything:
```
sudo wget -O flow-collector_7.2.2_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb && sudo mkdir -p elastiflow_extracted && sudo dpkg-deb -x flow-collector_7.2.2_linux_amd64.deb elastiflow_extracted && sudo mkdir -p /etc/elastiflow && sudo cp -r elastiflow_extracted/etc/elastiflow/. /etc/elastiflow
```
#### OPTIONAL: Geo and ASN Enrichment

If you would like to enable geo IP and ASN enrichment, please do the following:

1) Sign up for [Geolite2](https://www.maxmind.com/en/geolite2/signup) database access.
2) Download gzipped database files (GeoLite2 ASN and GeoLite2 City)
3) Extract their contents to `/etc/elastiflow/maxmind/`
4) Enable Geo and ASN enrichment in `elastiflow_flow_compose.yml`
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
  sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_flow_compose.yml up -d
  ```
#### 6) Log in to Kibana 

After a few minutes, browse to `http://IP_of_your_host:5601`.

Log in with:
Username: `elastic` 
Password: `elastic`

#### 7) Install ElastiFlow NetObserv Flow dashboards:

1) Download this [dashboards file](https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson) to your local machine.

2) Log in to Kibana.

3) Click menu, "Stack Management", then under the heading "Kibana", click "Saved Objects"
   
4) Browse for and upload the ndjson file you downloaded. Choose "import" and "overwrite".

#### 8) Send Netflow

  ##### Option 1: (Best)
  Send Netflow to IP_of_your_host:9995. Refer to your network hardware vendor for how to configure netflow / IPFIX / sFlow export.
  
  ##### Option 2: (OK)
  Generate flow data from one of your hosts  

  1) Install [Pmacct](http://www.pmacct.net/) on a machine somewhere
      ```
      sudo apt-get install pmacct
      ```
  2) Add the following Pmacct configuration to a new file located here `/etc/pmacct/pmacctd.conf`. Be sure to replace `NETWORK_INTERFACE_TO_MONITOR` with the name of an interface and `ELASTIFLOW_IP` with the IP address of your ElastiFlow NetObserv Flow server.

    daemonize: false
    pcap_interface: NETWORK_INTERFACE_TO_MONITOR
    aggregate: src_mac, dst_mac, src_host, dst_host, src_port, dst_port, proto, tos
    plugins: nfprobe, print
    nfprobe_receiver: ElastiFlow_NetObserv_Flow_IP:9995
    nfprobe_version: 9
    nfprobe_timeouts: tcp=15:maxlife=1800
    
    
  3) Run pmacct: `sudo pmacctd -f /etc/pmacct/pmacctd.conf`
    
  ##### Option 3: (Really?) 
  Generate fake flow data

  Be sure to replace `ElastiFlow_NetObserv_Flow_IP` with the IP address of your ElastiFlow NetObserv Flow server.

    sudo docker run -it --rm networkstatic/nflow-generator -t ElastiFlow_NetObserv_Flow_IP -p 9995

#### 9) Visualize your Flow Data
In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it. It may be a few minutes for flow records to populate as the system waits for flow templates to arrive.

#### 10) Update Credentials
Now that you have ElastiFlow NetObserv Flow up and running, we advise that you change your Elasticsearch and Kibana passwords from `elastic` to something complex as soon as possible. Here's how to do it:

1) Open your `.env` file in a text editor like nano.
2) Specify a new `ELASTIC_PASSWORD` and `KIBANA_PASSWORD`. Save changes.
3) Redeploy ElasticSearch, Kibana, ElastiFlow NetObserv Flow:
  ```
  sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_flow_compose.yml down && sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_flow_compose.yml up -d
  ```
# You did it! ^^^
More enrichments and functionality are available with a free [basic license](https://www.elastiflow.com/basic-license). You can also request a [30 day premium license](https://www.elastiflow.com/get-started) which unlocks broader device support, much higher flow rates, and all of the [NetIntel enrichments](https://www.elastiflow.com/blog/posts/elastiflow-launches-netintel-to-boost-enterprise-security-against-internal).
 
## Optional Enrichments

ElastiFlow NetObserv Flow is able to enrich flow records with many different pieces of data, making those records even more valuable, from app id, to threat information, geolocation, DNS hostnames, and more. Please click [here](https://docs.google.com/document/d/1Or-C5l5yVd7McVxwHUfE2mit_DvmtzHLAdUZhjnIKw8/edit?usp=sharing) for information on how to enable various enrichments.

## Notes

- If you need to make any ElastiFlow NetObserv Flow configuration changes such as turning options on and off, adding your license information, etc, go ahead and edit the elastiflow_flow_compose.yml and then running the following command: 
  ```
  sudo docker compose -f elastiflow_flow_compose.yml down && sudo docker compose -f elastiflow_flow_compose.yml up -d
  ```
- After making configuration changes, if ElastiFlow NetObserv Flow starts and then stops or fails to stay running, check the logs by doing
  ```
  sudo docker logs flow-collector -f
  ```
- If your server is has a different amount of RAM than 16GB, please view the .env file for guidance on the values for the following keys:

  `JVM_HEAP_SIZE`
  
  `MEM_LIMIT_ELASTIC`
  
  `MEM_LIMIT_KIBANA`

- Questions?
  [Documentation](https://docs.elastiflow.com) | [Community Forum](https://forum.elastiflow.com) | [Slack](https://elastiflowcommunity.slack.com) 
- Code in this folder may contain code from [Elastic's Github Repo.](https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker)

# BONUS

You can alternatively complete the whole installation with the following command

```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/install.sh)"
```


