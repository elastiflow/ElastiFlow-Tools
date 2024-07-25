
Code in this folder is from https://github.com/elastic/elasticsearch/tree/8.11/docs/reference/setup/install/docker

Purpose:
These instructions will install ElasticSearch 8.14.0, Kibana 8.14.0, and ElastiFlow 7.1.1 with Docker Compose.

1) Download all files to a new directory.

2) Edit the .env file to set your desired Kibana and Elastic passwords and Elastic stack version

      # Password for the 'elastic' user (at least 6 characters)
      ELASTIC_PASSWORD=

      # Password for the 'kibana_system' user (at least 6 characters)
      KIBANA_PASSWORD=

      # Version of Elastic products
      STACK_VERSION={version}

3) Run "sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d".

4) After a few minutes, browse to http://IP_of_your_host:5601. Username: "elastic", Password: your Elastic password you set in step 2

5) Install ElastiFlow dashboards:
      Download https://github.com/elastiflow/elastiflow_for_elasticsearch/blob/master/kibana/flow/kibana-8.2.x-flow-codex.ndjson
      In Kibana, do a global search (at the top) for "Saved Objects". Choose import and overwrite.

7) Send netflow to IP_of_your_host 9995

8) Visualize netflow
     In Kibana, do a global search (at the top) for the dashboard "ElastiFlow (flow): Overview" and open it.
