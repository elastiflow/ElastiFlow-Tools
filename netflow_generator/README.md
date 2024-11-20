README.md


The python script generates netflow v5 records. It uses a config.json to specify the configuration. This includes connection details for the collector (IP and Port)
and subnets you want to test with. During testing I observed roughly 4500FPS per process - you can run this multiple times to increase the FPS. I was able to 
generate over 13k FPS with 3 instances running. To run python3 netflowv5_gen.py --config config.json