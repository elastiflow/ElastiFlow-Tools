#!/usr/bin/env bash

install_flowcoll_monitor() {
  local script_path="/home/user/flowcoll_disk_space_monitor.sh"
  local service_name="flowcoll_disk_space_monitor"
  local log_file="/var/log/flowcoll_disk_space_monitor.log"

  if [[ ! -f "$script_path" ]]; then
    echo "Error: Monitoring script not found at $script_path"
    return 1
  fi

  chmod +x "$script_path"
  echo "Using external monitor script at $script_path"

  # Create systemd service
  cat <<EOF > "/etc/systemd/system/${service_name}.service"
[Unit]
Description=Flowcoll Disk Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=${script_path}
EOF

  # Create systemd timer
  cat <<EOF > "/etc/systemd/system/${service_name}.timer"
[Unit]
Description=Run Flowcoll Disk Monitor every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
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

install_flowcoll_monitor
