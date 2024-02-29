#!/bin/bash

interface="ens32"

#!/bin/bash

function verifyElastiFlow() {
    read -p "Do you want to verify if ElastiFlow is receiving and sending flow to Elastic? (y/n) " answer
    if [[ ${answer:0:1} =~ [yY] ]]; then
        echo "Installing pmacct..."
        sudo apt-get update && sudo apt-get install pmacct -y
        
        # Verify pmacct installation
        if ! command -v pmacctd &> /dev/null; then
            echo "pmacct installation failed."
            return 1
        fi
        
        echo "pmacct installed successfully."

        # Configure pmacct
        sudo mkdir -p /etc/pmacct/
        sudo bash -c "cat > /etc/pmacct/pmacctd.conf" <<EOF
daemonize: true
pcap_interface: $interface
aggregate: src_mac, dst_mac, src_host, dst_host, src_port, dst_port, proto, tos
plugins: nfprobe, print
nfprobe_receiver: localhost:9995
nfprobe_version: 9
nfprobe_timeouts: tcp=15:maxlife=1800
EOF

        # Start pmacctd
        echo "Starting pmacctd..."
        sudo pmacctd -f /etc/pmacct/pmacctd.conf &
        PMACCT_PID=$!

        echo "Generating network traffic (wget google.com)."
        for i in {1..5}; do
            wget -qO- http://google.com > /dev/null
        done

        # Terminate pmacct after 35 seconds
        echo -n "Terminating pmacct in 35 seconds... "
        for i in {3..1..-1}; do
            echo -ne "\rTerminating pmacct in $i seconds... "
            sleep 1
        done

        echo -e "\rTerminating pmacct...              "
        sudo kill $PMACCT_PID

        # Query Elasticsearch for ElastiFlow indices
        echo "Querying Elasticsearch for ElastiFlow indices..."
        response=$(curl -k -s -u elastic:elastic "http://localhost:9200/_cat/indices?format=json")
        if echo $response | jq -e '.[] | select(.index | contains("elastiflow"))' >/dev/null; then
            echo -e "\e[32mElastiFlow has been successfully verified.\e[0m"
        else
            echo "Something's wrong. No ElastiFlow indices found."
        fi
    else
        echo "Verification cancelled."
    fi
}

verifyElastiFlow

