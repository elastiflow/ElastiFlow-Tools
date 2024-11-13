What this is:
----------------
Script to easily install everything needed to monitor ElastiFlow using Prometheus and Grafana.

What this script does:
----------------
Downloads and installs Prometheus, Grafana, and ElastiFlow Grafana dashboards (all on an existing ElastiFlow server) for monitoring ElastiFlow metrics.

Requirements:
----------------
Existing ElastiFlow server
Docker (script can install this if it is missing)

Instructions:
----------------
1) sudo `./install_prof_graf.sh`
2) After installation is complete, you can access ElastiFlow metrics dashboard by logging in Grafana at `http://localhost:3000` (admin / admin)
