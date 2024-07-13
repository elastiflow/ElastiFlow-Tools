#!/bin/bash

LOG_FILE="/var/log/elastic_cleanup.log"
THRESHOLD=98
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

# Function to log error messages in red to both the screen and log file with timestamps
log_error() {
    echo -e "$(date): ${RED}$1${NC}" | tee -a $LOG_FILE
}

# Function to check if an index is the write index for the data stream
is_write_index() {
    local index=$1
    local write_indices=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_data_stream/$DATA_STREAM" | jq -r '.data_streams[0].indices[] | select(.index_name == "'$index'") | .index_name')
    if [[ $write_indices == *"$index"* ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to get the current and next write indices for the data stream
get_write_indices() {
    CURRENT_WRITE_INDEX=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_data_stream/$DATA_STREAM" | jq -r '.data_streams[0].indices[0].index_name')
    NEXT_WRITE_INDEX=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_data_stream/$DATA_STREAM" | jq -r '.data_streams[0].indices[1].index_name')
    log_message "Current write index: $CURRENT_WRITE_INDEX."
    log_message "Next write index: $NEXT_WRITE_INDEX."
}

# Function to get all eligible indices of the data stream, sorted by creation date
get_eligible_indices() {
    ALL_INDICES=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_cat/indices?h=index,creation.date&format=json" | jq -r '.[] | select(.index | contains("'"$DATA_STREAM"'")) | "\(.index) \(.creation.date)"' | sort -k2)
    log_message "ALL_INDICES content:\n$ALL_INDICES"
    ELIGIBLE_INDICES=$(echo "$ALL_INDICES" | grep -v "$CURRENT_WRITE_INDEX" | grep -v "$NEXT_WRITE_INDEX")
    if [ -z "$ALL_INDICES" ]; then
        log_message "No indices exist in the data stream."
        return 1
    elif [ -z "$ELIGIBLE_INDICES" ]; then
        log_message "The remaining indices are the current or next write index."
        return 1
    fi
    log_message "Eligible indices for deletion:\n$ELIGIBLE_INDICES"
    return 0
}

# Function to calculate the total size of all eligible indices
calculate_total_indices_size() {
    TOTAL_INDICES_SIZE=0
    while read -r INDEX; do
        INDEX_NAME=$(echo "$INDEX" | awk '{print $1}')
        INDEX_SIZE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/$INDEX_NAME/_stats/store" | jq -r '.indices[]._all.total.store.size_in_bytes')
        INDEX_SIZE_KB=$((INDEX_SIZE / 1024))
        TOTAL_INDICES_SIZE=$((TOTAL_INDICES_SIZE + INDEX_SIZE_KB))
    done <<< "$ELIGIBLE_INDICES"
    ESTIMATED_FREE_SPACE=$((INITIAL_FREE_SPACE + TOTAL_INDICES_SIZE))
    TOTAL_SPACE=$(df / | awk 'NR==2 {print $2}')
    ESTIMATED_FREE_SPACE_PERCENT=$((100 * ESTIMATED_FREE_SPACE / TOTAL_SPACE))
    log_message "Estimated free space after deleting eligible indices: $ESTIMATED_FREE_SPACE KB ($ESTIMATED_FREE_SPACE_PERCENT%)."
}

# Function to delete eligible indices
delete_eligible_indices() {
    while read -r INDEX; do
        INDEX_NAME=$(echo "$INDEX" | awk '{print $1}')

        # Check if the index is the current or next write index
        if [ $(is_write_index "$INDEX_NAME") == "true" ]; then
            log_message "Skipping deletion of write index $INDEX_NAME."
            continue
        fi

        DELETE_RESPONSE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -X DELETE "$ELASTIC_ENDPOINT/$INDEX_NAME" -s)
        DELETE_STATUS=$?

        if [ $DELETE_STATUS -ne 0 ]; then
            log_error "Failed to delete index $INDEX_NAME. Curl response: $DELETE_RESPONSE"
        else
            log_error "Deleted index $INDEX_NAME. Curl response: $DELETE_RESPONSE"
        fi
    done <<< "$ELIGIBLE_INDICES"
}

# Function to check disk space and delete indices if necessary
check_and_delete_indices() {
    while true; do
        USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        FREE_SPACE=$((100 - USED_SPACE))
        log_message "Current free space on root partition: $FREE_SPACE%."

        if [ "$FREE_SPACE" -lt $THRESHOLD ]; then
            log_message "Free space is $FREE_SPACE%, which is below the threshold of $THRESHOLD%."
            INITIAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
            log_message "Initial free space: $INITIAL_FREE_SPACE KB."
            get_write_indices
            get_eligible_indices
            if [ $? -ne 0 ]; then
                NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
                log_message "Next check will run at $NEXT_RUN_TIME."
                sleep $CHECK_INTERVAL
                continue
            fi
            calculate_total_indices_size
            log_error "Deleting eligible indices."
            delete_eligible_indices
            USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
            FREE_SPACE=$((100 - USED_SPACE))
            log_message "Deleted eligible indices. Free space is now $FREE_SPACE%."
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
