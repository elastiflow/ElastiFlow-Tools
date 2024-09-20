
Code in this folder may contain code from https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker

ElastiFlow Environment with Docker
================================  

## Author
[O.J. Wolanyk]

### Purpose:
To easily install ElasticSearch, Kibana, and ElastiFlow with Docker Compose. Tested with Elastic / Kibana 8.15.1 and ElastiFlow 7.2.2.

### Prerequisites:
-Clean Ubuntu 22 (or greater) server

-8 GB of RAM, 4 CPU cores, and 500 GB of disk.

-Docker. 

If you do not have Docker, you can install it by:
1) downloading "install_docker.sh" to your Linux server.
2) `sudo chmod +x install_docker.sh && ./install_docker.sh`
   
   OR simply can use this one liner

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

You could instead use the following one liner to do the same:

```
echo -e "\n# Memory mapping limits for Elasticsearch\nvm.max_map_count=262144\n# Network settings for high performance\nnet.core.netdev_max_backlog=4096\nnet.core.rmem_default=262144\nnet.core.rmem_max=67108864\nnet.ipv4.udp_rmem_min=131072\nnet.ipv4.udp_mem=2097152 4194304 8388608" | sudo tee -a /etc/sysctl.conf > /dev/null && sudo sysctl -p
```

##### Explanation of parameters:

`vm.max_map_count=262144`

Description: This parameter sets the maximum number of memory map areas a process can have. Memory maps are used by programs like Elasticsearch to map files to memory for faster access.
Use case: Elasticsearch (and other large JVM applications) makes heavy use of memory-mapped files for efficient access to its index files. If this value is too low, Elasticsearch might fail to start or run efficiently.
Default value: On many systems, the default is much lower (e.g., 65530), so setting it to 262144 ensures Elasticsearch has enough room to handle its memory mappings.

`net.core.netdev_max_backlog=4096`

Description: This parameter specifies the maximum number of packets allowed to queue up for processing at the network interface. If the network driver can't process packets fast enough, they are buffered in this queue.
Use case: For systems handling high traffic or many connections, increasing this value ensures that packets are not dropped if they arrive faster than the system can process them. A value of 4096 means that up to 4096 packets can be queued before the system starts dropping them.

`net.core.rmem_default=262144`

Description: This sets the default size of the receive buffer used by sockets (in bytes). This buffer temporarily stores incoming data before it's processed by the application.
Use case: For applications that receive a large amount of data, like Elasticsearch, setting a higher default receive buffer size improves performance by allowing the system to handle larger amounts of data before dropping packets or slowing down.

`net.core.rmem_max=67108864`

Description: This defines the maximum size (in bytes) for the receive buffer for a socket. Applications can request a buffer size up to this limit.
Use case: When dealing with high-throughput applications, increasing the maximum receive buffer size allows the system to handle larger bursts of incoming data. The value of 67108864 means that the system can allocate up to 64 MB for the receive buffer of a socket.

`net.ipv4.udp_rmem_min=131072`

Description: This parameter sets the minimum size (in bytes) of the receive buffer used by UDP sockets.
Use case: For systems handling a lot of UDP traffic (such as logging or monitoring applications that rely on UDP), setting a higher minimum receive buffer ensures that the system can handle incoming data without dropping packets due to small buffer sizes. The value 131072 (128 KB) helps in maintaining adequate buffer size for UDP traffic.

`net.ipv4.udp_mem=2097152 4194304 8388608`

Description: This defines the memory usage limits for UDP sockets. It consists of three values (in pages, where 1 page is usually 4096 bytes):
2097152 (2 GB): This is the threshold where the kernel starts applying memory pressure to slow down the socket to prevent further memory allocation.
4194304 (4 GB): The kernel starts dropping packets when memory allocation reaches this point.
8388608 (8 GB): This is the absolute maximum memory the kernel will allocate for UDP traffic.
Use case: For systems with high-volume UDP traffic, these values help ensure that the system has enough memory allocated for UDP packet buffering before dropping packets or causing errors.

#### 2) Disable swapping

View current swap configuration `swapon --show`

If swap is active, you'll see the details of the swap partitions or files. 

If there is a swap partition, then `sudo nano /etc/fstab` and comment out or remove the swap entry: In the /etc/fstab file, look for the line that defines the swap partition or file.  It usually looks something like this:
`/swapfile none swap sw 0 0`.

If there is a swap file, then use the following command, replacing `swapfile.img` with the name of your swap file returned with 
```
swapon --show
NAME      TYPE SIZE USED PRIO
/swap.img file   4G   0B   -2
```

`sudo swapoff -a && rm /swap.img`

Reboot and verify swap is off with `swapon --show`

#### 3) Download 
Create a new directory on your server and download the following files to it:

https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env
https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml"
https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_compose.yml

Or copy and paste the following in a terminal session:
```
curl -L -o ".env" "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/.env"
curl -L -o "elasticsearch_kibana_compose.yml" "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elasticsearch_kibana_compose.yml"
curl -L -o "elastiflow_compose.yml" "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/elastiflow_compose.yml"
curl -L -o "readme.md" "https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/readme.md"
```

#### 4) Set variables / Edit the .env file
Edit the .env file to set your desired Kibana and Elastic passwords, Elastic stack version, and ElastiFlow version to deploy. You may not see this file in your directory since it is hidden, but it is there.

#### 5) Download sample yml enrichment files
Download ElastiFlow from here: 
https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb

Extract the contents of `/etc/elastiflow` in the archive to `/etc/elastiflow`.

You can instead use a one liner to do everything:
```
sudo wget -O flow-collector_7.2.2_linux_amd64.deb https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb && sudo mkdir -p elastiflow_extracted && dpkg-deb -x flow-collector_7.2.2_linux_amd64.deb elastiflow_extracted && sudo mkdir -p /etc/elastiflow && sudo cp -r elastiflow_extracted/etc/elastiflow/. /etc/elastiflow
```
#### 6) Deploy 
```
sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d
```
#### 7) Log in to Kibana 

After a few minutes, browse to `http://IP_of_your_host:5601`.

Username: `elastic` Password: `your Elastic password you specified in your .env file`

#### 8) Install ElastiFlow dashboards:
Download https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson

In Kibana, do a global search (at the top) for "Saved Objects". Choose "import" and "overwrite".

#### 9) Send Netflow
Send Netflow to IP_of_your_host 9995. Refer to your hardware vendor for documentation on how to configure netflow export.

#### 10) Visualize netflow
In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it.


