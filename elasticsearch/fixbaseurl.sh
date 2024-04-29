#!/bin/bash

handle_error() {
    local error_msg="$1"
    local line_num="$2"
    local user_decision

    echo "Error at line $line_num: $error_msg"
    echo "Do you wish to continue? (y/n):"
    read user_decision

    if [[ $user_decision == "y" ]]; then
        echo "Continuing execution..."
    elif [[ $user_decision == "n" ]]; then
        echo "Exiting..."
        exit 1
    else
        echo "Invalid input. Exiting..."
        exit 1
    fi
}
# Replace text in a file with error handling
replace_text() {
    local file_path="$1"
    local old_text="$2"
    local new_text="$3"
    local line_num="$4"
    sed -i.bak "s|$old_text|$new_text|g" "$file_path" || handle_error "Failed to replace text in $file_path." "$line_num"
}


kibana_config_path="/etc/kibana/kibana.yml"
replace_text "$kibana_config_path" '#server.publicBaseUrl: ""' 'server.publicBaseUrl: "http://kibana.example.com:5601"' "${LINENO}"
