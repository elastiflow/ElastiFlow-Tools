#!/bin/bash

LOG_FILE="/var/log/elastic_cleanup.log"
THRESHOLD=25
CHECK_INTERVAL=30

function log_message {
    echo "$(date): $1" >> $LOG_FILE
}

while true; do
    # Get the percentage of free space on the root partition
    FREE_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$FREE_SPACE" -lt $THRESHOLD ]; then
        log_message "Free space is $FREE_SPACE%, which is below the threshold of $THRESHOLD%."

        # Get the initial free space
        INITIAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')

        while [ "$FREE_SPACE" -lt $THRESHOLD ]; do
            # Delete the oldest shard
            OLDEST_SHARD=$(curl -s "http://localhost:9200/_cat/shards?h=index,shard,prirep,state,unassigned.reason,store,ip,node,creation.date" | sort -k8 | head -n 1 | awk '{print $1}')
            curl -X DELETE "http://localhost:9200/$OLDEST_SHARD" -s

            # Get the new percentage of free space
            FREE_SPACE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

            log_message "Deleted shard $OLDEST_SHARD. Free space is now $FREE_SPACE%."
        done

        # Get the final free space
        FINAL_FREE_SPACE=$(df / | awk 'NR==2 {print $4}')
        log_message "Free space increased from $INITIAL_FREE_SPACE to $FINAL_FREE_SPACE after deletions."

    else
        log_message "Free space is $FREE_SPACE%, which is above the threshold of $THRESHOLD%."
    fi

    sleep $CHECK_INTERVAL
done
