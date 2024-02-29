#!/bin/bash

interface="ens32"

function verifyElastiFlow() {

# Step 1: List all indices and filter by those containing "elastiflow"
indices=$(curl -s -X GET "http://localhost:9200/_cat/indices/*elastiflow*?h=index" | tr '\n' ' ')

# Check if the list is empty
if [ -z "$indices" ]; then
    echo "No indices containing 'elastiflow' were found."
    exit 0
fi

echo "Found indices containing 'elastiflow': $indices"

# Step 2: For each index found, check if it has more than one document
for index in $indices; do
    count=$(curl -s -X GET "http://localhost:9200/$index/_count" -H 'Content-Type: application/json' -d'
    {
      "query": {
        "match_all": {}
      }
    }' | jq '.count')

    if [ "$count" -gt 1 ]; then
        echo "Index $index has more than 1 document."
        exit 0
    fi
done

echo "None of the 'elastiflow' indices have more than 1 document."


verifyElastiFlow
