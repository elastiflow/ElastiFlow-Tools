
ElastiFlow NetObserv Flow + Opensearch Full Stack Deployment with Docker - Redhat based Linux
================================  

## Author
[Pat Vogelsang]

### Purpose:
To easily install Opensource and ElastiFlow NetObserv Flow with Docker Compose on a RedHat based Linux distribution. Tested with Elastic / Kibana 8.15.1 and ElastiFlow NetObserv Flow 7.5.0.

### Instructions:
 Follow all the guidlines in the [README.MD](https://github.com/elastiflow/ElastiFlow-Tools/blob/main/docker_install/opensearch/readme.md) file in the docker_install directory of this github distribution. Except for any changes documented below

- Docker. If you do not have Docker, you can install it with the following one liner:
  ```
  sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/redhat_elasticsearch/install_docker.sh)"
  ```

### Instructions:
# BONUS

You can alternatively complete the whole installation with the following command:

```
sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/elastiflow/ElastiFlow-Tools/main/docker_install/redhat_opensearch/install.sh)"
```


