#!/bin/bash
# Install Spark Application Exporter on Prometheus Server

set -e

echo "=== Installing Spark Application Exporter ==="

# Install Python dependencies
echo "Installing Python dependencies..."
sudo dnf update -y
sudo dnf install -y python3 python3-pip

# Install required Python packages
pip3 install --user prometheus_client requests

# Create application directory
sudo mkdir -p /opt/spark-app-exporter
sudo chown ec2-user:ec2-user /opt/spark-app-exporter

# Copy exporter script
echo "Copying exporter script..."
cp spark_app_exporter.py /opt/spark-app-exporter/
chmod +x /opt/spark-app-exporter/spark_app_exporter.py

# Install systemd service
echo "Installing systemd service..."
sudo cp ../config/service-files/spark-app-exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable spark-app-exporter

# Start the service
echo "Starting Spark Application Exporter..."
sudo systemctl start spark-app-exporter

# Check status
echo "Checking service status..."
sudo systemctl status spark-app-exporter --no-pager

echo ""
echo "=== Installation Complete ==="
echo "Exporter is running on port 8081"
echo "Metrics endpoint: http://localhost:8081/metrics"
echo ""
echo "To check logs: sudo journalctl -u spark-app-exporter -f"
echo "To restart: sudo systemctl restart spark-app-exporter"
