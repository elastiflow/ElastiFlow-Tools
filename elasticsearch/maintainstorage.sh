#!/bin/bash

# Elasticsearch endpoint and credentials
ES_HOST="https://localhost:9200"
ES_USER="elastic"
ES_PASS="elastic"

# Index pattern to manage
INDEX_PATTERN="elastiflow-*"

# Minimum free disk space in KB (15 GB)
MIN_FREE_SPACE=$((15 * 1024 * 1024))

# Function to get the available disk space
get_free_disk_space() {
  df -P / | awk 'NR==2 {print $4}'
}

# Function to delete the oldest index
delete_oldest_index() {
  oldest_index=$(curl -s -u "$ES_USER:$ES_PASS" -X GET "${ES_HOST}/_cat/indices/${INDEX_PATTERN}?h=index&sort=index" | head -n 1)
  if [ -n "$oldest_index" ]; then
    echo "Deleting oldest index: $oldest_index"
    curl -s -u "$ES_USER:$ES_PASS" -X DELETE "${ES_HOST}/${oldest_index}"
  fi
}

# Main loop
free_space=$(get_free_disk_space)

echo "Available disk space: $free_space KB"
echo "Minimum required free space: $MIN_FREE_SPACE KB"

if (( free_space < MIN_FREE_SPACE )); then
  echo "Free space is below the threshold. Deleting oldest index..."
  delete_oldest_index
else
  echo "Free space is within the acceptable range."
fi
