get_host_ip() {
    # List all network interfaces except docker and lo
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(docker|lo)' | head -n 1)

    if [ -z "$INTERFACE" ]; then
        echo "No suitable network interface found."
        return 1
    else
        # Get the IP address of the interface
        ip_address=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}' | cut -d/ -f1)

        if [ -z "$ip_address" ]; then
            echo "No IP address found for interface $INTERFACE."
            return 1
        else
            echo "$ip_address"
            return 0
        fi
    fi
}

# Call the function and store the result in a variable
ip_address=$(get_host_ip)
printf "ip address: $ip_address"

# Check if an IP address was returned
if [ -z "$ip_address" ]; then
    echo "No IP address found for any suitable interface."
else
    echo "IP address of the interface: $ip_address"
fi
