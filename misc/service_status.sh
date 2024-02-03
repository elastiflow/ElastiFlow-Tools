#!/bin/bash

# Function to check the status of a service
check_service_status() {
    service_name=$1
    status=$(systemctl is-active $service_name 2>/dev/null)

    if [ "$status" = "active" ]; then
        echo "$service_name is running"
    elif [ "$status" = "inactive" ]; then
        echo "$service_name is inactive"
    else
        echo "Cannot determine the status of $service_name"
    fi
}

# Check the status of four services
check_service_status "elasticsearch.service"
check_service_status "kibana.service"
check_service_status "flowcoll.service"
check_service_status "suricata.service"
check_service_status "filebeat.service"
