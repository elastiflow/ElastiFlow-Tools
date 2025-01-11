#!/bin/bash
# 
# Version: 1.0
#
# This script will copy all the dashboard that contain "elastiflow" in the title
# along with all the components of the dashbaords from the default kibana space
# to a user specifcied kibana space
#
# IP:PORT andCredentials are read form .env file in same directory as the bash script
# Destination Kibana space is passed as an argument to the script
#
# ./migrate-ef-kibana-objectsa.sh <DESINATION KIBANA SPACE NAME>
#

check_space() {
    echo "Checking if the Kibana space '$SPACE_NAME' exists..."

    # Call the Kibana API to list spaces
    response=$(curl -s -u "$USERNAME:$PASSWORD" \
    -X GET "http://$KIBANA_IP:$KIBANA_PORT/api/spaces/space?" \
    -H "kbn-xsrf: true")

    # Check if the API call was successful
    if [ $? -ne 0 ]; then
        echo "Failed to connect to Kibana. Please check your settings."
        exit 1
    fi

    # Look for the space name in the response
    if echo "$response" | grep -q "\"id\":\"$SPACE_NAME\""; then
        echo "The Kibana space '$SPACE_NAME' exists."
        # exit 0
    else
        echo "The Kibana space '$SPACE_NAME' does not exist."
        exit 1
    fi
}
#
# By default the script looks for all dashboards with elastiflow in the title 
# you can change that with variable SEACRH_STRING
#
SEACRH_STRING='elastiflow'

# Check if required arguments are provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <KIBANA_SPACE_NAME>"
  exit 1
fi
SPACE_NAME="$1"

#
# Verfiy that .env exists 
# If it does not create a default .env file
#
if [ -f ".env" ]; then
    echo "The .env file already exists in the current directory."
    source .env
else
    echo "The .env file does not exist. Creating a new .env file..."
    cat <<EOL > .env
KIBANA_IP=127.0.0.1
KIBANA_PORT=5601
USERNAME=elastic
PASSWORD=elastic
EOL
    echo "The .env file has been created with default values."
    echo "modify .env with your specific values and run script again"
    exit 1
fi
#
# Verify all required fields were configured in the .env file
#
required_vars=("KIBANA_IP" "KIBANA_PORT" "USERNAME" "PASSWORD")
missing_vars=()

# Check if each required variable is set
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

# Handle missing variables
if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "The following required variables are missing or empty in your .env file:"
    for var in "${missing_vars[@]}"; do
        echo "- $var"
    done
    exit 1
fi
#
# Check to see if the destination space exists
#
check_space

# Temporary files for IDs
DASHBOARD_IDS_FILE="dashboard-ids"
VISUALIZATION_IDS_FILE="visualization-ids"

# Collect Dashboard IDs in the default Kibana space
#
echo "Collecting ElastiFlow NetObserv Kibana Dashboard IDs..."
curl -s -X GET "http://$KIBANA_IP:5601/api/saved_objects/_find?type=dashboard&search=$SEACRH_STRING&search_fields=title&per_page=1000" \
  -H "kbn-xsrf: true" \
  -u "$USERNAME:$PASSWORD" | jq -r '.saved_objects[] | .id' > "$DASHBOARD_IDS_FILE"

# Collect Visualization IDs
echo "Collecting ElastiFlow NetObserv Kibana Visualization IDs..."
curl -s -X GET "http://$KIBANA_IP:5601/api/saved_objects/_find?type=visualization&search=$SEACRH_STRING&search_fields=title&per_page=1000" \
  -H "kbn-xsrf: true" \
  -u "$USERNAME:$PASSWORD" | jq -r '.saved_objects[] | .id' > "$VISUALIZATION_IDS_FILE"

# Build JSON payload
echo "Building JSON payload..."
objects_json="["
while read -r id; do
  if [ -n "$id" ]; then
    objects_json+="{\"type\": \"dashboard\", \"id\": \"$id\"},"
  fi
done < "$DASHBOARD_IDS_FILE"

while read -r id; do
  if [ -n "$id" ]; then
    objects_json+="{\"type\": \"visualization\", \"id\": \"$id\"},"
  fi
done < "$VISUALIZATION_IDS_FILE"

# Remove trailing comma and close JSON array
objects_json="${objects_json%,}]"

# Create the JSON payload file
JSON_PAYLOAD_FILE="payload.json"
cat <<EOF > "$JSON_PAYLOAD_FILE"
{
  "spaces": ["$SPACE_NAME"],
  "objects": $objects_json,
  "includeReferences": true,
  "compatibilityMode": true,
  "createNewCopies": false
}
EOF

# Submit the payload to the Kibana API
echo "Submitting payload to Kibana API..."
curl -s -X POST "http://$KIBANA_IP:5601/api/spaces/_copy_saved_objects" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$USERNAME:$PASSWORD" \
  -d @"$JSON_PAYLOAD_FILE"

echo "Migration process completed."

# Cleanup temporary files
rm -f "$DASHBOARD_IDS_FILE" "$VISUALIZATION_IDS_FILE" "$JSON_PAYLOAD_FILE"