

1) Download all files to a new directory.
2) Edit .env file to set your desired Kibana and Elastic passwords.
3) run "sudo docker compose -f elasticsearch_kibana_compose.yml -f elastiflow_compose.yml up -d
4) After a few minutes, browse to http://IP_of_your_host:5601. Username: Password: your Elastic password you set in step 2
