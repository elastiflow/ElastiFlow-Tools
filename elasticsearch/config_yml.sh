#!/bin/bash

# Function to perform find and replace
comment_and_add_line() {
  local FILE=$1
  local FIND=$2
  local REPLACE=$3

  # Check if the line exists and if it's already commented out
  if grep -q "^$FIND" "$FILE"; then
    # If the line is not commented out, comment it out and add the new line underneath
    sed -i.bak "/^$FIND/s/^/#/; /^$FIND/a $REPLACE" "$FILE"
    echo "Commented out '$FIND' and added '$REPLACE' underneath."
  elif grep -q "^#$FIND" "$FILE"; then
    # If the line is already commented out, just add the new line underneath
    sed -i.bak "/^#$FIND/a $REPLACE" "$FILE"
    echo "Found commented out line '$FIND'. Added '$REPLACE' underneath."
  else
    # Add the line under the heading #ElastiFlow VA installer
    if grep -q "^#ElastiFlow VA installer" "$FILE"; then
      sed -i.bak "/^#ElastiFlow VA installer/a $REPLACE" "$FILE"
      echo "Added '$REPLACE' under the heading '#ElastiFlow VA installer'."
    else
      echo "Heading '#ElastiFlow VA installer' not found in the file."
      echo "Add the heading '#ElastiFlow VA installer' to the file and run the script again."
      exit 1
    fi
  fi
}

# Function to process an array of find and replace strings
find_and_replace() {
  local FILE=$1
  shift
  local PAIRS=("$@")

  # Check if the file exists
  if [ ! -f "$FILE" ]; then
    echo "File not found!"
    exit 1
  fi

  # Loop through the pairs of find and replace strings
  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    local FIND=${PAIRS[i]}
    local REPLACE=${PAIRS[i+1]}
    comment_and_add_line "$FILE" "$FIND" "$REPLACE"
  done

  # Verify if the operation was successful
  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    local REPLACE=${PAIRS[i+1]}
    if grep -qF "$REPLACE" "$FILE"; then
      echo "Verified: '$REPLACE' is in the file."
    else
      echo "Verification failed: '$REPLACE' is not in the file."
    fi
  done
}

# Example usage
FILE="path/to/your/file"
STRINGS_TO_REPLACE=(
  "EF_LICENSE_ACCEPTED" 'EF_LICENSE_ACCEPTED: "true"'
  "EF_ACCOUNT_ID" 'EF_ACCOUNT_ID: ""'
  "EF_FLOW_LICENSE_KEY" 'EF_FLOW_LICENSE_KEY: ""'
  "EF_OUTPUT_ELASTICSEARCH_ENABLE" 'EF_OUTPUT_ELASTICSEARCH_ENABLE: "true"'
  "EF_OUTPUT_ELASTICSEARCH_ADDRESSES" 'EF_OUTPUT_ELASTICSEARCH_ADDRESSES: 127.0.0.1:9200'
  "EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE" 'EF_OUTPUT_ELASTICSEARCH_ECS_ENABLE: "true"'
  "EF_OUTPUT_ELASTICSEARCH_PASSWORD" 'EF_OUTPUT_ELASTICSEARCH_PASSWORD: "$elastic_password"'
  "EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE" 'EF_OUTPUT_ELASTICSEARCH_TLS_ENABLE: "true"'
  "EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION" 'EF_OUTPUT_ELASTICSEARCH_TLS_SKIP_VERIFICATION: "true"'
  "EF_FLOW_SERVER_UDP_IP" 'EF_FLOW_SERVER_UDP_IP: 0.0.0.0'
  "EF_FLOW_SERVER_UDP_PORT" 'EF_FLOW_SERVER_UDP_PORT: 2055,4739,6343,9995'
  "EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE" 'EF_FLOW_SERVER_UDP_READ_BUFFER_MAX_SIZE: 33554432'
  "EF_PROCESSOR_DECODE_IPFIX_ENABLE" 'EF_PROCESSOR_DECODE_IPFIX_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_MAX_RECORDS_PER_PACKET" 'EF_PROCESSOR_DECODE_MAX_RECORDS_PER_PACKET: 64'
  "EF_PROCESSOR_DECODE_NETFLOW1_ENABLE" 'EF_PROCESSOR_DECODE_NETFLOW1_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_NETFLOW5_ENABLE" 'EF_PROCESSOR_DECODE_NETFLOW5_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_NETFLOW6_ENABLE" 'EF_PROCESSOR_DECODE_NETFLOW6_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_NETFLOW7_ENABLE" 'EF_PROCESSOR_DECODE_NETFLOW7_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_NETFLOW9_ENABLE" 'EF_PROCESSOR_DECODE_NETFLOW9_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_SFLOW5_ENABLE" 'EF_PROCESSOR_DECODE_SFLOW5_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_SFLOW_COUNTERS_ENABLE" 'EF_PROCESSOR_DECODE_SFLOW_COUNTERS_ENABLE: "true"'
  "EF_PROCESSOR_DECODE_SFLOW_FLOWS_ENABLE" 'EF_PROCESSOR_DECODE_SFLOW_FLOWS_ENABLE: "true"'
)

find_and_replace "$FILE" "${STRINGS_TO_REPLACE[@]}"
