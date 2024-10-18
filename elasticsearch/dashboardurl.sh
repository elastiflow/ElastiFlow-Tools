get_dashboard_url() {
  local kibana_url="http://$ip_address:5601"
  local dashboard_title="$1"
  encoded_title=$(echo "$dashboard_title" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/(/%28/g' | sed 's/)/%29/g')
  local encoded_title
  response=$(curl -s -u "$elastic_username:$elastic_password2" -X GET "$kibana_url/api/saved_objects/_find?type=dashboard&search_fields=title&search=$encoded_title" -H 'kbn-xsrf: true')
  local response
  dashboard_id=$(echo "$response" | jq -r '.saved_objects[] | select(.attributes.title=="'"$dashboard_title"'") | .id')
  local dashboard_id
  if [ -z "$dashboard_id" ]; then
    echo "Dashboard not found"
  else
    echo "$kibana_url/app/kibana#/dashboard/$dashboard_id"
  fi
}
