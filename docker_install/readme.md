
Code in this folder may contain code from https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker

### Purpose:
To easily install ElasticSearch, Kibana, and ElastiFlow with Docker Compose. Tested with Elastic / Kibana 8.15.1 and ElastiFlow 7.2.2.

### Prerequisites:
 Clean Ubuntu 22 (or greater) server with at least 8 GB of RAM, 4 CPU cores, and 500 GB of disk.

Docker. If you do not have Docker, you can install it by:
1) downloading "install_docker.sh" to your Linux server.
2) `sudo chmod +x install_docker.sh && ./install_docker.sh`

### Instructions:

#### 1) Add the following recommended Kernel tuning parameters to /etc/sysctl.conf

```vm.max_map_count=262144
net.core.netdev_max_backlog=4096
net.core.rmem_default=262144
net.core.rmem_max=67108864
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_mem=2097152 4194304 8388608
```
To activate the settings, run `sysctl -p`

#### 2) Create the following directory:
`/etc/elastiflow/`

#### 3) Disable swapping

View current swap configuration `swapon --show`

If swap is active, you'll see the details of the swap partitions or files. 

If there is a swap partition, then `sudo nano /etc/fstab` and comment out or remove the swap entry: In the /etc/fstab file, look for the line that defines the swap partition or file.  It usually looks something like this:
`/swapfile none swap sw 0 0`.

If there is a swap file, then use the following command, replacing `swapfile.img` with the name of your swap file returned with `swapon --show`.

`sudo swapoff -a && rm /swapfile.img`

Reboot and verify swap is off with `swapon --show`

#### 4) Download 
Download all files in the docker_install folder to a new directory on a Linux host.

#### 5) Edit the .env file
Edit the .env file to set your desired Kibana and Elastic passwords, Elastic stack version, and ElastiFlow version to deploy

#### 6) Deploy 
Run `sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d`

After a few minutes, browse to http://IP_of_your_host:5601. Username: `elastic`", Password: your Elastic password you set in step 2.

#### 7) Install ElastiFlow dashboards:
Download https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson
In Kibana, do a global search (at the top) for "Saved Objects". Choose import and overwrite.

#### 8 Send Netflow
Send Netflow to IP_of_your_host 9995. Refer to your hardware vendor for documentation on how to configure netflow export.

#### 9) Visualize netflow
In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it.
