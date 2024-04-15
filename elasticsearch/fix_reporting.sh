printf "\n\n\n*********Generating Kibana saved objects encryption key...\n\n"
# Run the command to generate encryption keys quietly
output=$(/usr/share/kibana/bin/kibana-encryption-keys generate -q)

# Extract the line that starts with 'xpack.reporting.encryptionKey'
key_line=$(echo "$output" | grep '^xpack.encryptedSavedObjects.encryptionKey')

# Check if the key line was found
if [[ -n "$key_line" ]]; then
    # Append the key line to /etc/kibana/kibana.yml
    echo "$key_line" | sudo tee -a /etc/kibana/kibana.yml > /dev/null
else
    echo "No encryption key line found."
fi

printf "\n\n\n*********Restarting Kibana and Elastic services...\n\n"
systemctl daemon-reload && systemctl restart kibana.service && systemctl restart elasticsearch.service
