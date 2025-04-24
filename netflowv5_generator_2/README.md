The python script generates netflow v5 records. It uses a config.json to specify the configuration. This includes connection details for the collector (IP and Port)
and subnets you want to test with. The script will use completly random IPs if subnets are not specified.  During testing I observed roughly 4500FPS per process. The Script will spawn additional processes based on the FPS specified in the configuration file i.e. 20k FPS will spawn 5 processes. Please refer to the config.json below for a description of all fields. This can also be used in conjunction with netif.yml also in this repo for interface testing. The netif.yml includes 10k devices and 100 interfaces per device. The netif.py can be used to create other netif.yml files. 

    "_comment_flows_per_second": "Configures the flows per second. Every 4000 FPS will spawn another process",
    "flows_per_second": 10000,
  
    "_comment_collector_ip": "Collector IP you are sending flow to",
    "collector_ip": "10.101.2.171",
  
    "_comment_collector_port": "Collector port - this is currently hard coded to 2055",
    "collector_port": 2055,
  
    "_comment_number_of_exporters": "Number of emulated devices sending flow",
    "number_of_exporters": 10000,
  
    "_comment_source_packet_subnet": "Source IP of the NetFlow packets being sent to the collector",
    "source_packet_subnet": "10.10.0.0/16",
  
    "_comment_source_ip_subnet": "Source IP of the sessions in the NetFlow packet",
    "source_ip_subnet": "192.168.0.0/24",
  
    "_comment_destination_ip_subnet": "Destination IP of the sessions in the NetFlow packet",
    "destination_ip_subnet": "10.0.0.0/24",
    
    "_comment_source_ports": "source port that is generted for the flow record. This can be a range, comma seperated or the work random",
    "source_ports": "1024-65535",
    
    "_comment_destination_ports": "source port that is generted for the flow record. This can be a range, comma seperated or the work random",
    "destination_ports": "22,80,443,8080"