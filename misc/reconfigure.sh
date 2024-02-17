get_enp_interface_ip() {
    # Get the first network interface starting with enp
    INTERFACE=$(ip -o link show | grep -o 'enp[^:]*' | head -n 1)

    if [ -z "$INTERFACE" ]; then
        echo "No interface starting with 'enp' found." >&2
        return 1
    else
        # Get the IP address of the interface
        IP_ADDRESS=$(ip -o -4 addr show $INTERFACE | awk '{print $4}' | cut -d/ -f1)

        if [ -z "$IP_ADDRESS" ]; then
            echo "No IP address found for interface $INTERFACE." >&2
            return 2
        else
            echo "$IP_ADDRESS"
        fi
    fi
}

ip_address=$(get_enp_interface_ip)
if [ $? -eq 0 ]; then
    echo "The IP address is $ip_address"
else
    echo "Failed to get IP address."
fi


