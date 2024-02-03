#!/bin/bash

# Function to check the status of a service and display in color
check_service_status() {
    service_name=$1
    status=$(systemctl is-active $service_name 2>/dev/null)

    if [ "$status" = "active" ]; then
        echo -e "\e[32m$service_name is running\e[0m"  # Green color
    elif [ "$status" = "inactive" ]; then
        echo -e "\e[31m$service_name is inactive\e[0m"  # Red color
    else
        echo -e "\e[31mCannot determine the status of $service_name\e[0m"  # Red color
    fi
}

# Check the status of four services
check_service_status "elasticsearch.service"
check_service_status "kibana.service"
check_service_status "flowcoll.service"
check_service_status "suricata.service"
check_service_status "filebeat.service"
