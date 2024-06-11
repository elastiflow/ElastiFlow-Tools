#!/bin/bash


get_network_interface_ip() {
    # Get the first network interface starting with en
    INTERFACE=$(ip -o link show | grep -o 'en[^:]*' | head -n 1)

    if [ -z "$INTERFACE" ]; then
        echo ""
        return 1
    else
        # Get the IP address of the interface
        ip_address=$(ip -o -4 addr show $INTERFACE | awk '{print $4}' | cut -d/ -f1)

        if [ -z "$ip_address" ]; then
            echo ""
            return 1
        else
            echo "$ip_address"
            return 0
        fi
    fi
}
