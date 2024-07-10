#!/bin/bash

LOG_FILE="/var/log/elastic_cleanup.log"
THRESHOLD=25
CHECK_INTERVAL=5

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

        # Get the current write index for the data stream
        CURRENT_WRITE_INDEX=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_data_stream/$DATA_STREAM" | jq -r '.data_streams[0].indices[0].index_name')
        log_message "Current write index: $CURRENT_WRITE_INDEX."

        while [ "$FREE_SPACE" -lt $THRESHOLD ]; do
            log_message "Attempting to identify the oldest shard of the data stream to free up space."

            # Get the oldest shard of the specified data stream excluding the current write index
            OLDEST_SHARD=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/_cat/shards?h=index,shard,prirep,state,unassigned.reason,store,ip,node,creation.date" | grep "$DATA_STREAM" | grep -v "$CURRENT_WRITE_INDEX" | sort -k8 | head -n 1 | awk '{print $1}')

            if [ -z "$OLDEST_SHARD" ]; then
                log_message "No shards available for deletion in the specified data stream."
                break
            fi

            log_message "Oldest shard identified: $OLDEST_SHARD."

            # Estimate free space after deletion
            SHARD_SIZE=$(curl -k -u "$ELASTIC_USERNAME:$ELASTIC_PASSWORD" -s "$ELASTIC_ENDPOINT/$OLDEST_SHARD/_stats/store" | jq -r '.indices[]._all.total.store.size_in_bytes')
            ESTIMATED_FREE_SPACE=$((INITIAL_FREE_SPACE + SHARD_SIZE / 1024))
            ESTIMATED_FREE_SPACE_PERCENT=$(df / | awk 'NR==2 {print ($4 + '$SHARD_SIZE' / 1024) / ($2 / 100)}')
            log_message "Estimated free space after deleting shard $OLDEST_SHARD: $ESTIMATED_FREE_SPACE KB ($ESTIMATED_FREE_SPACE_PERCENT%)."

            if [ "$ESTIMATED_FREE_SPACE_PERCENT" -ge "$THRESHOLD" ]; then
                # Prompt user for confirmation before deletion
                read -p "Deleting shard $OLDEST_SHARD will increase free space to $ESTIMATED_FREE_SPACE_PERCENT%. Do you want to delete it? (y/n): " CONFIRMATION

                if [ "$CONFIRMATION" != "y" ]; then
                    log_message "User chose not to delete the shard $OLDEST_SHARD."
                    break
                fi

                log_message "Deleting shard: $OLDEST_SHARD."

                # Delete the shard
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
                break
            else
                log_message "Deleting shard $OLDEST_SHARD will not attain the free space target."
                break
            fi
        done

        # Get the final free space
        FINAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
        log_message "Free space before delete: $INITIAL_FREE_SPACE KB. Free space after delete: $FINAL_FREE_SPACE KB."

    else
        log_message "Free space is $FREE_SPACE%, which is above the threshold of $THRESHOLD%."
    fi

    NEXT_RUN_TIME=$(date -d "now + $CHECK_INTERVAL seconds" "+%Y-%m-%d %H:%M:%S")
    log_message "Next check will run at $NEXT_RUN_TIME."

    sleep $CHECK_INTERVAL
done
