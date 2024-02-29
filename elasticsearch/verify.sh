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
        interface="YOUR_NETWORK_INTERFACE_HERE" # Replace with your actual network interface
        sudo mkdir -p /etc/pmacct/
        echo
        
        "daemonize: true
        pcap_interface: $interface
        aggregate: src_mac, dst_mac, src_host, dst_host, src_port, dst_port, proto, tos
        plugins: nfprobe, print
        nfprobe_receiver: localhost:9995
        nfprobe_version: 9
        nfprobe_timeouts: tcp=15:maxlife=1800" | sudo tee /etc/pmacct/pmacctd.conf
        
        # Start pmacctd
        echo "Starting pmacctd..."
        sudo pmacctd -f /etc/pmacct/pmacctd.conf &
        PMACCT_PID=$!

        echo "Generating network traffic (wget google.com)."
        for i in {1..5}; do
            wget -qO- http://google.com > /dev/null
        done

        # Terminate pmacct after 35 seconds
        echo -n "Terminating pmacct in 35 seconds..."
        for i in {35..1..-1}; do
            echo -ne "\r$i seconds remaining..."
            sleep 1
        done

        echo -e "\rTerminating pmacct...         "
        sudo kill $PMACCT_PID

        # Query Kibana for ElastiFlow indices
        echo "Querying Kibana for ElastiFlow indices..."
        ELASTIFLOW_INDICES=$(curl -s "http://localhost:5601/api/console/proxy?path=_cat/indices%2Felastiflow-*&method=GET" | jq -r '.[] | select(.index | contains("elastiflow")) | .index')

        if [[ ! -z "$ELASTIFLOW_INDICES" ]]; then
            echo "ElastiFlow has been successfully verified."
        else
            echo "Something's wrong. No ElastiFlow indices found."
        fi
    else
        echo "Verification cancelled."
    fi
}

verifyElastiFlow
