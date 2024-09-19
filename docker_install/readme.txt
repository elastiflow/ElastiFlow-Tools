
Code in this folder may contain code from https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker

Purpose:
=================
To easily install ElasticSearch, Kibana, and ElastiFlow with Docker Compose. Tested with Elastic / Kibana 8.15.1 and ElastiFlow 7.2.2.

Prerequisites:
=================
1) Clean Linux server with at least 8 GB of RAM, 4 CPU cores, and 500 GB of disk.
2) Docker. If you do not have docker, you can install it by:
      1) downloading "install_docker.sh" to your Linux server.
      2) "sudo chmod +x install_docker.sh && ./install_docker.sh"

Instructions:
=================
1) Prepare server.

For software like Elasticsearch, increasing vm.max_map_count is recommended because Elasticsearch creates many memory mappings (pointers stored in RAM that point to disk locations) due to its heavy use of Lucene indexes. Elasticsearch documentation suggests increasing it to at least 262144 to avoid problems in production.
      
      On Linux, you can increase the limits by running the following command as root:
      "sysctl -w vm.max_map_count=262144"
      To set this value permanently, update the vm.max_map_count setting in /etc/sysctl.conf. To verify after rebooting or enter “sysctl -p”, run sysctl vm.max_map_count.

Create the following directory:
/etc/elastiflow/
      
2) Download all files in the docker_install folder to a new directory on a Linux host.

3) Edit the .env file to set your desired Kibana and Elastic passwords, Elastic stack version, and ElastiFlow version to deploy

      # Password for the 'elastic' user (at least 6 characters)
      ELASTIC_PASSWORD={elastic_password}

      # Password for the 'kibana_system' user (at least 6 characters)
      KIBANA_PASSWORD={kibana_password}

      # Version of Elastic products
      STACK_VERSION={version}

      # Elastiflow Version
      ELASTIFLOW_VERSION={version}

4) Run "sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d".

5) After a few minutes, browse to http://IP_of_your_host:5601. Username: "elastic", Password: your Elastic password you set in step 2.

6) Install ElastiFlow dashboards:
      Download https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson
      In Kibana, do a global search (at the top) for "Saved Objects". Choose import and overwrite.

7) Send Netflow to IP_of_your_host 9995. Refer to your hardware vendor for documentation.

8) Visualize netflow
     In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it.
