
Code in this folder may contain code from https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker

Purpose:
To easily install ElasticSearch, Kibana, and ElastiFlow with Docker Compose. Tested with Elastic / Kibana 8.14.0 and ElastiFlow 7.1.1.

1) Prepare server memory configuration

      Elasticsearch uses a mmapfs directory by default to store its indices. The default operating system limits on mmap counts is likely to be too low, which may result in out of             memory exceptions.
      
      On Linux, you can increase the limits by running the following command as root:
      
      sysctl -w vm.max_map_count=262144
      
      To set this value permanently, update the vm.max_map_count setting in /etc/sysctl.conf. To verify after rebooting or enter “sysctl -p”, run sysctl vm.max_map_count.
      
      To verify changes, after rebooting, run sysctl vm.max_map_count

2) Download all files to a new directory.

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

5) After a few minutes, browse to http://IP_of_your_host:5601. Username: "elastic", Password: your Elastic password you set in step 2

6) Install ElastiFlow dashboards:
      Download https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson
      In Kibana, do a global search (at the top) for "Saved Objects". Choose import and overwrite.

7) Send Netflow to IP_of_your_host 9995

8) Visualize netflow
     In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it.
