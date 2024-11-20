What this is:
----------------
Script to easily install everything needed to monitor ElastiFlow using Prometheus and Grafana.

## Author
[O.J. Wolanyk]

What this script does:
----------------
Downloads and installs Prometheus, Grafana, and ElastiFlow Grafana dashboards (all on an existing ElastiFlow server) for monitoring ElastiFlow metrics.

Requirements:
----------------
ElastiFlow server configured with metrics enabled on port 8080. In `/etc/elastiflow/flowcoll.yml` the key / value pair you need is: `EF_API_PORT: 8080`

Docker (script can install this if it is missing)

Instructions:
----------------
1) Download everything in this folder into the home directory of an existing ElastiFlow server. Then, sudo `./install_prof_graf.sh`
2) After installation is complete, you can access ElastiFlow metrics dashboard by logging in Grafana at `http://localhost:3000` (admin / admin)
