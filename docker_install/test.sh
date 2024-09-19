#!/bin/bash

# Set variables
DEB_URL="https://elastiflow-releases.s3.us-east-2.amazonaws.com/flow-collector/flow-collector_7.2.2_linux_amd64.deb"
DEB_FILE="flow-collector_7.2.2_linux_amd64.deb"
TEMP_DIR="/tmp/elastiflow_deb"
TARGET_DIR="/etc/elastiflow"

# Download the .deb file
echo "Downloading $DEB_URL..."
wget -O "$DEB_FILE" "$DEB_URL"

# Check if the temporary directory exists; if not, create it
if [ ! -d "$TEMP_DIR" ]; then
    echo "Creating directory $TEMP_DIR..."
    mkdir -p "$TEMP_DIR"
else
    echo "$TEMP_DIR already exists, skipping creation."
fi

# Extract the .deb file contents
echo "Extracting $DEB_FILE..."
dpkg-deb -x "$DEB_FILE" "$TEMP_DIR"

# Copy /data/etc/elastiflow contents to /etc/elastiflow
echo "Copying extracted files to $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
cp -r "$TEMP_DIR/data/etc/elastiflow/." "$TARGET_DIR/"

# Cleanup
echo "Cleaning up..."
rm -rf "$TEMP_DIR" "$DEB_FILE"

echo "Done!"
