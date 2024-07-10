#!/bin/bash

LOG_FILE="/var/log/elastic_cleanup.log"
THRESHOLD=25
CHECK_INTERVAL=30

# Set Elasticsearch credentials
ELASTIC_USERNAME="elastic"
ELASTIC_PASSWORD="elastic"

# Elasticsearch endpoint and data stream
ELASTIC_ENDPOINT="https://localhost:9200"
DATA_STREAM="elastiflow-flow-ecs-8.0-2.3-tsds"

# Function to log messages to both the screen and log file with timestamps
log_message() {
    echo "$(date): $1" | tee -a $LOG_FILE
}

while true; do
    # Get the percentage of free space on the root partition
    FREE_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    log_message "Current free space on root partition: $FREE_SPACE%."

    if [ "$FREE_SPACE" -lt $THRESHOLD ]; then
        log_message "Free space is $FREE_SPACE%, which is below the threshold of $THRESHOLD%."

        # Get the initial free space
        INITIAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
        log_message "Initial free space: $INITIAL_FREE_SPACE KB."

        while [ "$FREE_SPACE" -lt $THRESHOLD ]; do
            log_message "Attempting to delete the oldest shard to free up space."

            # Get the oldest shard
            OLDEST_SHARD=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_cat/shards?h=index,shard,prirep,state,unassigned.reason,store,ip,node,creation.date" | sort -k8 | head -n 1 | awk '{print $1}')
            
            if [ -z "$OLDEST_SHARD" ]; then
                log_message "No shards available for deletion."
                break
            fi

            log_message "Deleting oldest shard: $OLDEST_SHARD."

            # Delete the oldest shard
            DELETE_RESPONSE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -X DELETE "$ELASTIC_ENDPOINT/$OLDEST_SHARD" -s)
            DELETE_STATUS=$?

            if [ $DELETE_STATUS -ne 0 ]; then
                log_message "Failed to delete shard $OLDEST_SHARD. Curl response: $DELETE_RESPONSE"
                continue
            else
                log_message "Deleted shard $OLDEST_SHARD. Curl response: $DELETE_RESPONSE"
            fi

            # Get the new percentage of free space
            FREE_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
            log_message "Deleted shard $OLDEST_SHARD. Free space is now $FREE_SPACE%."
        done

        # Get the final free space
        FINAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
        log_message "Free space increased from $INITIAL_FREE_SPACE KB to $FINAL_FREE_SPACE KB after deletions."

    else
        log_message "Free space is $FREE_SPACE%, which is above the threshold of $THRESHOLD%."
    fi

    NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
    log_message "Next check will run at $NEXT_RUN_TIME."

    sleep $CHECK_INTERVAL
done
