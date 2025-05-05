#!/bin/bash

install_flow_blocker() {
  local script_path="/usr/local/bin/flow_blocker.sh"
  local service_path="/etc/systemd/system/flow_blocker.service"

  echo -e "\n📦 Installing dependencies..."
  sudo apt-get update -qq

  # Suppress iptables-persistent install prompts
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections

  sudo apt-get install -y iptables iptables-persistent

  echo -e "\n🔧 Creating flow_blocker script at $script_path..."

  sudo tee "$script_path" > /dev/null << 'EOF'
#!/bin/bash

threshold_free_space_low=70
threshold_free_space_ok=75
interval=30
ports="9995 2055 4739 6343"
es_url="https://localhost:9200"
es_curl_opts="-k -s"
es_auth=""
log_file="/var/log/flow_blocker.log"

log() {
  msg="[$(date)] $*"
  echo "$msg" | tee -a "$log_file"
}

broadcast() {
  msg="[$(date)] $*"
  echo "$msg" | tee -a "$log_file" | wall -n
}

ensure_firewall_ready() {
  if ! command -v iptables &>/dev/null; then
    log "Installing iptables..."
    apt-get update -qq && apt-get install -y iptables
  fi

  if ! lsmod | grep -q '^ip_tables'; then
    log "Loading ip_tables kernel module..."
    modprobe ip_tables
  fi
}

enable_flow_block() {
  ensure_firewall_ready
  local changed=false

  for port in $ports; do
    if ! iptables -C OUTPUT -p udp -d 127.0.0.1 --dport "$port" -m comment --comment "flow_block_$port" -j DROP 2>/dev/null; then
      iptables -A OUTPUT -p udp -d 127.0.0.1 --dport "$port" -m comment --comment "flow_block_$port" -j DROP
      broadcast "⚠️ Flow block ENABLED: Blocking UDP to 127.0.0.1:$port due to low disk space"
      changed=true
    fi
  done

  if [ "$changed" = true ]; then
    iptables-save > /etc/iptables/rules.v4
    log "🔒 Persisted block rules to /etc/iptables/rules.v4"
  fi
}

disable_flow_block() {
  ensure_firewall_ready
  local changed=false

  for port in $ports; do
    if iptables -C OUTPUT -p udp -d 127.0.0.1 --dport "$port" -m comment --comment "flow_block_$port" -j DROP 2>/dev/null; then
      iptables -D OUTPUT -p udp -d 127.0.0.1 --dport "$port" -m comment --comment "flow_block_$port" -j DROP
      broadcast "✅ Flow block DISABLED: Unblocked UDP to 127.0.0.1:$port (disk space recovered)"
      changed=true
    fi
  done

  if [ "$changed" = true ]; then
    iptables-save > /etc/iptables/rules.v4
    log "🔓 Persisted unblock rules to /etc/iptables/rules.v4"
  fi
}

get_free_disk_pct_fallback() {
  df_output=$(df --output=avail,size -B1 / | tail -n1)
  avail_bytes=$(echo $df_output | awk '{print $1}')
  total_bytes=$(echo $df_output | awk '{print $2}')
  echo $(echo "scale=2; 100 * $avail_bytes / $total_bytes" | bc -l)
}

while true; do
  disk_json=$(curl $es_curl_opts $es_auth "$es_url/_nodes/stats/fs?filter_path=nodes.*.fs.total")
  available=$(echo "$disk_json" | jq '[.nodes[].fs.total.available_in_bytes] | min')
  total=$(echo "$disk_json" | jq '[.nodes[].fs.total.total_in_bytes] | max')

  if [[ -z "$available" || -z "$total" || "$available" == "null" || "$total" == "null" ]]; then
    broadcast "❌ Could not retrieve Elasticsearch stats. Using OS-level fallback."
    free_pct=$(get_free_disk_pct_fallback)
  else
    free_pct=$(echo "scale=2; 100 * $available / $total" | bc -l)
  fi

  log "🧮 Free disk space: ${free_pct}%"

  if (( $(echo "$free_pct <= $threshold_free_space_low" | bc -l) )); then
    enable_flow_block
  elif (( $(echo "$free_pct > $threshold_free_space_ok" | bc -l) )); then
    disable_flow_block
  fi

  sleep $interval
done
EOF

  sudo chmod +x "$script_path"

  echo -e "\n🧷 Creating systemd service at $service_path..."

  sudo tee "$service_path" > /dev/null << EOF
[Unit]
Description=Flow Blocker (based on Elasticsearch disk space)
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=$script_path
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  echo -e "\n🔄 Reloading and enabling service..."

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable --now flow_blocker.service

  echo -e "\n✅ flow_blocker.service is active and will start on boot."
}

install_flow_blocker
