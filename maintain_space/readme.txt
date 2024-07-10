Service Configuration (/etc/systemd/system/check_free_space.service)
Create a systemd service file to run the script as a service.

ini
Copy code
[Unit]
Description=Check Free Space and Clean Elasticsearch Shards
After=network.target

[Service]
Type=simple
ExecStart=/path/to/check_free_space.sh
Restart=always

[Install]
WantedBy=multi-user.target
Instructions
Save the Shell Script: Save the script as check_free_space.sh and make it executable.

chmod +x /path/to/check_free_space.sh
Create the Systemd Service: Save the service configuration file as /etc/systemd/system/check_free_space.service.

Reload Systemd: Reload systemd to recognize the new service.

systemctl daemon-reload
Start the Service: Start and enable the service to run at boot.

systemctl start check_free_space.service
systemctl enable check_free_space.service
Check Logs: You can check the log file at /var/log/elastic_cleanup.log for deletion logs.
