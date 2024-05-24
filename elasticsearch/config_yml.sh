#!/bin/bash


replace_or_add_line() {
  local FILE=$1
  local FIND=$2
  local REPLACE=$3

  # Check if the line exists
  if grep -q "^$FIND" "$FILE"; then
    # Use sed to replace the line
    sed -i.bak "s/^$FIND.*/$REPLACE/" "$FILE"
    echo "Replaced '$FIND' with '$REPLACE'."
  else
    # Add the line under the heading #ElastiFlow VA installer
    sed -i.bak "/#ElastiFlow VA installer/a $REPLACE" "$FILE"
    echo "Added '$REPLACE' under the heading '#ElastiFlow VA installer'."
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
    replace_or_add_line "$FILE" "$FIND" "$REPLACE"
  done

  # Verify if the operation was successful
  for ((i = 0; i < ${#PAIRS[@]}; i+=2)); do
    local REPLACE=${PAIRS[i+1]}
    if grep -q "^$REPLACE" "$FILE"; then
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
  "ANOTHER_STRING" 'ANOTHER_STRING: "value"'
)

find_and_replace "$FILE" "${STRINGS_TO_REPLACE[@]}"
