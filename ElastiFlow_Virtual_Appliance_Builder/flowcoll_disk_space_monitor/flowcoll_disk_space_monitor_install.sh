#!/usr/bin/env bash

install_flowcoll_disk_space_monitor() {
  local script_path="/home/user/flowcoll_disk_space_monitor.sh"
  local service_name="flowcoll_disk_space_monitor"
  local log_file="/var/log/flowcoll_disk_space_monitor/flowcoll_disk_space_monitor.log"

  if [[ ! -f "$script_path" ]]; then
    echo "Error: Monitoring script not found at $script_path"
    return 1
  fi

  mkdir -p "/var/log/flowcoll_disk_space_monitor/"
  
  chmod +x "$script_path"
  echo "Using external monitor script at $script_path"

  # Create systemd service
  cat <<EOF > "/etc/systemd/system/${service_name}.service"
[Unit]
Description=Flowcoll Disk Space Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=${script_path}
EOF

  # Create systemd timer
  cat <<EOF > "/etc/systemd/system/${service_name}.timer"
[Unit]
Description=Run Flowcoll Disk Space Monitor every 30 seconds

[Timer]
OnBootSec=2min
OnUnitActiveSec=30sec
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Reload systemd and start timer
  systemctl daemon-reload
  systemctl enable --now "${service_name}.timer"

  echo "Installed and started ${service_name}.timer"
  echo "Log output will appear in: ${log_file}"
}

setup_flowcoll_logrotate() {
  local logrotate_config="/etc/logrotate.d/flowcoll"

  # Check if logrotate is installed, install if not
  if ! dpkg -s logrotate >/dev/null 2>&1; then
    echo "logrotate not found — installing..."
    sudo apt-get update && sudo apt-get install -y logrotate
  else
    echo "logrotate is already installed."
  fi

  # Create the logrotate config
  sudo tee "${logrotate_config}" > /dev/null <<EOF
/var/log/flowcoll_disk_space_monitor/flowcoll_disk_space_monitor.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

  echo "Logrotate config created at ${logrotate_config}"
}


install_flowcoll_disk_space_monitor
setup_flowcoll_logrotate
