README.md


The python script generates netflow v5 records. It uses a config.json to specify the configuration. This includes connection details for the collector (IP and Port)
and subnets you want to test with. The script will use completly random IPs if subnets are not specified.  During testing I observed roughly 4500FPS per process. The Script will spawn additional processes based on the FPS specified in the configuration file i.e. 20k FPS will spawn 5 processes. 
