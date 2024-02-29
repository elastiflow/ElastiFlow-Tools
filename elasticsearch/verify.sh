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

        echo "Generating network traffic (wget google.com)."
        for i in {1..5}; do
            wget -qO- http://google.com > /dev/null
        done

        # Terminate pmacct after 35 seconds
        echo -n "Terminating pmacct in 35 seconds... "
        for i in {35..1..-1}; do
            echo -ne "\rTerminating pmacct in $i seconds... "
            sleep 1
        done

        echo -e "\rTerminating pmacct...              "
        sudo killall pmacctd

# Step 1: List all indices and filter by those containing "elastiflow"
indices=$(curl -s -X GET "http://localhost:9200/_cat/indices/*elastiflow*?h=index" | tr '\n' ' ')

        # Check if the list is empty
        if [ -z "$indices" ]; then
            echo "No indices containing 'elastiflow' were found."
            exit 0
        fi
        
        echo "Found indices containing 'elastiflow': $indices"
        
        # Step 2: For each index found, check if it has more than one document
        for index in $indices; do
            count=$(curl -s -X GET "http://localhost:9200/$index/_count" -H 'Content-Type: application/json' -d'
            {
              "query": {
                "match_all": {}
              }
            }' | jq '.count')
        
            if [ "$count" -gt 1 ]; then
                echo "Index $index has more than 1 document."
                exit 0
            fi
        done

echo "None of the 'elastiflow' indices have more than 1 document."
    else
        echo "Verification cancelled."
    fi
}

verifyElastiFlow

