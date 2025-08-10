#!/bin/bash

# Script to clean up Prometheus installation on EMR cluster

set -e

PROMETHEUS_DIR="/opt/prometheus"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"

echo "Cleaning up Prometheus installation..."

# Stop and disable Prometheus service
echo "Stopping Prometheus service..."
sudo systemctl stop prometheus || echo "Prometheus service not running"
sudo systemctl disable prometheus || echo "Prometheus service not enabled"
sudo rm -f /etc/systemd/system/prometheus.service
sudo systemctl daemon-reload

# Remove Prometheus files
echo "Removing Prometheus files..."
sudo rm -rf $PROMETHEUS_DIR
sudo rm -rf $CONFIG_DIR
sudo rm -rf $DATA_DIR

# Remove Prometheus user
echo "Removing Prometheus user..."
sudo userdel prometheus || echo "User prometheus does not exist"

echo "Prometheus cleanup completed successfully"