
wget https://elastiflow-releases.s3.us-east-2.amazonaws.com/snmp-collector/snmp-collector_6.4.3_linux_amd64.deb
apt install libpcap-dev
sudo apt install ./snmp-collector_6.4.3_linux_amd64.deb
sudo systemctl daemon-reload && sudo systemctl start snmpcoll.service



