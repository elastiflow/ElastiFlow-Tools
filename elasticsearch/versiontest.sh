#!/bin/bash

# URL of the changelog page
URL="https://docs.elastiflow.com/docs/changelog"

# Fetch the page content
content=$(curl -s $URL)

# Extract the version number (assuming the latest version is the first h3 header on the page)
version=$(echo "$content" | grep -oP '(?<=<h3>).+?(?=</h3>)' | head -n 1)

# Print the version number
echo "Latest version: $version"
