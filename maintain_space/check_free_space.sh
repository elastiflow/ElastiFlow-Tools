#!/bin/bash

LOG_FILE="/var/log/elastic_cleanup.log"
THRESHOLD=97
CHECK_INTERVAL=5

# Set Elasticsearch credentials
ELASTIC_USERNAME="elastic"
ELASTIC_PASSWORD="elastic"

# Elasticsearch endpoint and data stream
ELASTIC_ENDPOINT="https://localhost:9200"
DATA_STREAM="elastiflow-flow-codex-2.3-tsds"

# Function to log messages to both the screen and log file with timestamps
log_message() {
    echo "$(date): $1" | tee -a $LOG_FILE
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

# Function to get all eligible shards of the data stream
get_eligible_shards() {
    ALL_SHARDS=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_cat/shards?h=index,shard,prirep,state,unassigned.reason,store,ip,node,creation.date" | grep "$DATA_STREAM")
    log_message "ALL_SHARDS content: $ALL_SHARDS"
    ELIGIBLE_SHARDS=$(echo "$ALL_SHARDS" | grep -v "$CURRENT_WRITE_INDEX" | grep -v "$NEXT_WRITE_INDEX")
    if [ -z "$ALL_SHARDS" ]; then
        log_message "No shards exist in the data stream."
        return 1
    elif [ -z "$ELIGIBLE_SHARDS" ]; then
        log_message "The remaining shards are the current or next write index."
        return 1
    fi
    log_message "Eligible shards for deletion: $ELIGIBLE_SHARDS"
    return 0
}

# Function to calculate the total size of all eligible shards
calculate_total_shards_size() {
    TOTAL_SHARDS_SIZE=0
    while read -r SHARD; do
        SHARD_NAME=$(echo "$SHARD" | awk '{print $1}')
        SHARD_SIZE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/$SHARD_NAME/_stats/store" | jq -r '.indices[]._all.total.store.size_in_bytes')
        SHARD_SIZE_KB=$((SHARD_SIZE / 1024))
        TOTAL_SHARDS_SIZE=$((TOTAL_SHARDS_SIZE + SHARD_SIZE_KB))
    done <<< "$ELIGIBLE_SHARDS"
    ESTIMATED_FREE_SPACE=$((INITIAL_FREE_SPACE + TOTAL_SHARDS_SIZE))
    TOTAL_SPACE=$(df / | awk 'NR==2 {print $2}')
    ESTIMATED_FREE_SPACE_PERCENT=$((100 * ESTIMATED_FREE_SPACE / TOTAL_SPACE))
    log_message "Estimated free space after deleting eligible shards: $ESTIMATED_FREE_SPACE KB ($ESTIMATED_FREE_SPACE_PERCENT%)."
}

# Function to delete eligible shards
delete_eligible_shards() {
    while read -r SHARD; do
        SHARD_NAME=$(echo "$SHARD" | awk '{print $1}')
        SHARD_NUMBER=$(echo "$SHARD" | awk '{print $2}')

        # Check if the shard is part of the current or next write index
        if [ $(is_write_index "$SHARD_NAME") == "true" ]; then
            log_message "Skipping deletion of write index shard $SHARD_NAME (shard number: $SHARD_NUMBER)."
            continue
        fi

        DELETE_RESPONSE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -X DELETE "$ELASTIC_ENDPOINT/$SHARD_NAME" -s)
        DELETE_STATUS=$?

        if [ $DELETE_STATUS -ne 0 ]; then
            log_message "Failed to delete shard $SHARD_NAME (shard number: $SHARD_NUMBER). Curl response: $DELETE_RESPONSE"
        else
            log_message "Deleted shard $SHARD_NAME (shard number: $SHARD_NUMBER). Curl response: $DELETE_RESPONSE"
        fi
    done <<< "$ELIGIBLE_SHARDS"
}

# Function to check disk space and delete shards if necessary
check_and_delete_shards() {
    while true; do
        USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        FREE_SPACE=$((100 - USED_SPACE))
        log_message "Current free space on root partition: $FREE_SPACE%."

        if [ "$FREE_SPACE" -lt $THRESHOLD ]; then
            log_message "Free space is $FREE_SPACE%, which is below the threshold of $THRESHOLD%."
            INITIAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
            log_message "Initial free space: $INITIAL_FREE_SPACE KB."
            get_write_indices
            get_eligible_shards
            if [ $? -ne 0 ]; then
                NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
                log_message "Next check will run at $NEXT_RUN_TIME."
                sleep $CHECK_INTERVAL
                continue
            fi
            calculate_total_shards_size
            read -p "Deleting all eligible shards will increase free space to $ESTIMATED_FREE_SPACE_PERCENT%. Do you want to delete them? (y/n): " CONFIRMATION
            if [ "$CONFIRMATION" != "y" ]; then
                log_message "User chose not to delete the eligible shards."
                NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
                log_message "Next check will run at $NEXT_RUN_TIME."
                sleep $CHECK_INTERVAL
                continue
            fi
            log_message "Deleting eligible shards."
            delete_eligible_shards
            USED_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
            FREE_SPACE=$((100 - USED_SPACE))
            log_message "Deleted eligible shards. Free space is now $FREE_SPACE%."
        else
            log_message "Free space is $FREE_SPACE%, which is above the threshold of $THRESHOLD%."
        fi

        NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
        log_message "Next check will run at $NEXT_RUN_TIME."
        sleep $CHECK_INTERVAL
    done
}

# Main script execution
check_and_delete_shards
