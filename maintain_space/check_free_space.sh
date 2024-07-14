#!/bin/bash

SCRIPT_NAME=$(basename "$0")
LOG_FILE="/var/log/${SCRIPT_NAME%.*}.log"
THRESHOLD=97
CHECK_INTERVAL=5

# Set Elasticsearch credentials
ELASTIC_USERNAME="elastic"
ELASTIC_PASSWORD="elastic"

# Elasticsearch endpoint and data stream
ELASTIC_ENDPOINT="https://localhost:9200"
DATA_STREAM="elastiflow-flow-codex-2.3-tsds"

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to log messages to both the screen and log file with timestamps
log_message() {
    echo -e "$(date): $1" | tee -a $LOG_FILE
}

# Function to log important messages in red to both the screen and log file with timestamps
log_important_msg() {
    echo -e "$(date): ${RED}****************$1${NC}" | tee -a $LOG_FILE
}

# Function to get all eligible indices of the data stream and sort them by creation date
get_eligible_indices() {
    ALL_INDICES=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_cat/indices?v&h=index,creation.date.string" | grep "$DATA_STREAM" | sort -k2)
    
    log_message "ALL_INDICES content:\nindex creation.date.string\n$ALL_INDICES"
    
    ELIGIBLE_INDICES=$(echo "$ALL_INDICES")
    
    if [ -z "$ALL_INDICES" ]; then
        log_message "No indices exist in the data stream."
        return 1
    elif [ $(echo "$ELIGIBLE_INDICES" | wc -l) -le 2 ]; then
        log_message "Only two or fewer indices left. No deletion performed."
        return 1
    fi
    
    log_message "Eligible indices for deletion:\nindex creation.date.string\n$ELIGIBLE_INDICES"
    
    return 0
}

# Function to delete a single eligible index and verify deletion
delete_one_eligible_index() {
    local index_name=$(echo "$1" | awk '{print $1}')

    DELETE_RESPONSE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -X DELETE "$ELASTIC_ENDPOINT/$index_name" -s)
    DELETE_STATUS=$?

    if [ $DELETE_STATUS -ne 0 ]; then
        log_important_msg "Failed to delete index $index_name. Curl response: $DELETE_RESPONSE"
        return 1
    else
        # Verify deletion
        VERIFY_RESPONSE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/$index_name")
        if [[ $VERIFY_RESPONSE == *"index_not_found_exception"* ]]; then
            log_important_msg "Deleted index $index_name. Curl response: $DELETE_RESPONSE"
            return 0
        else
            log_important_msg "Failed to verify deletion of index $index_name. Curl response: $VERIFY_RESPONSE"
            return 1
        fi
    fi
}

# Function to check disk space and delete indices if necessary
check_and_delete_indices() {
    while true; do
        USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        FREE_SPACE=$((100 - USED_SPACE))
        log_message "Current free space on root partition: $FREE_SPACE%."

        if [ "$FREE_SPACE" -lt $THRESHOLD ]; then
            log_message "Free space is $FREE_SPACE%, which is below the threshold of $THRESHOLD%."
            get_eligible_indices
            if [ $? -ne 0 ]; then
                NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
                log_message "Next check will run at $NEXT_RUN_TIME."
                sleep $CHECK_INTERVAL
                continue
            fi
            
            while read -r INDEX; do
                log_important_msg "Deleting eligible index: $INDEX"
                delete_one_eligible_index "$INDEX"
                if [ $? -eq 0 ]; then
                    break
                fi
            done <<< "$ELIGIBLE_INDICES"

            USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
            FREE_SPACE=$((100 - USED_SPACE))
            log_message "Deleted eligible index. Free space is now $FREE_SPACE%."
        else
            log_message "Free space is $FREE_SPACE%, which is above the threshold of $THRESHOLD%."
        fi

        NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
        log_message "Next check will run at $NEXT_RUN_TIME."
        sleep $CHECK_INTERVAL
    done
}

# Main script execution
check_and_delete_indices
