#!/bin/bash

# Script to install Prometheus on EMR cluster and configure it to scrape Kyuubi metrics
# and send them to the demo-emr workspace in AWS Managed Prometheus

set -e

# Use a known working version of Prometheus
PROMETHEUS_VERSION="2.45.0"
MIDP_WORKLOAD_NAME="midp-batch"
WORKSPACE_ID="ws-748ea42c-587e-4634-8eef-48accc4619d7" # demo-emr
PROMETHEUS_DIR="/opt/prometheus"
CONFIG_DIR="/etc/prometheus"
AWS_REGION="us-east-1"

echo "Installing Prometheus on EMR cluster $MIDP_WORKLOAD_NAME..."

# Create directories
sudo mkdir -p $PROMETHEUS_DIR
sudo mkdir -p $CONFIG_DIR

# Detect system architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  PROMETHEUS_ARCH="arm64"
else
  PROMETHEUS_ARCH="amd64"
fi

echo "Detected system architecture: $ARCH, using Prometheus build for $PROMETHEUS_ARCH"

# Download and install Prometheus
cd /tmp
echo "Downloading Prometheus version ${PROMETHEUS_VERSION} for ${PROMETHEUS_ARCH}..."
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}.tar.gz
tar -xzf prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}.tar.gz

# Check if the extracted directory exists and has the expected structure
if [ ! -d "prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}" ]; then
  echo "Error: Prometheus extraction failed. Directory not found."
  exit 1
fi

# Copy binary files
sudo cp prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/prometheus $PROMETHEUS_DIR/ || { echo "Error: prometheus binary not found"; exit 1; }
sudo cp prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/promtool $PROMETHEUS_DIR/ || { echo "Error: promtool binary not found"; exit 1; }

# Copy console files if they exist
if [ -d "prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/consoles" ]; then
  sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/consoles $PROMETHEUS_DIR/
else
  echo "Note: consoles directory not found in this Prometheus version, creating empty directory"
  sudo mkdir -p $PROMETHEUS_DIR/consoles
fi

# Copy console libraries if they exist
if [ -d "prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/console_libraries" ]; then
  sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}/console_libraries $PROMETHEUS_DIR/
else
  echo "Note: console_libraries directory not found in this Prometheus version, creating empty directory"
  sudo mkdir -p $PROMETHEUS_DIR/console_libraries
fi

# Clean up downloaded files
rm -rf prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH} prometheus-${PROMETHEUS_VERSION}.linux-${PROMETHEUS_ARCH}.tar.gz

# Create prometheus user
sudo useradd --no-create-home --shell /bin/false prometheus || echo "User prometheus already exists"
sudo chown -R prometheus:prometheus $PROMETHEUS_DIR
sudo chown -R prometheus:prometheus $CONFIG_DIR

# Create prometheus configuration
cat > /tmp/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "${MIDP_WORKLOAD_NAME}"
    __aws_emr_cluster_name: "${MIDP_WORKLOAD_NAME}"

scrape_configs:
  - job_name: 'kyuubi'
    static_configs:
      - targets: ['localhost:10019']
        labels:
          service: 'kyuubi'

remote_write:
  - url: "https://aps-workspaces.${AWS_REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write"
    queue_config:
      max_samples_per_send: 1000
      max_shards: 200
      capacity: 2500
    sigv4:
      region: ${AWS_REGION}
EOF

sudo mv /tmp/prometheus.yml $CONFIG_DIR/
sudo chown prometheus:prometheus $CONFIG_DIR/prometheus.yml

# Create systemd service
cat > /tmp/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=$PROMETHEUS_DIR/prometheus \
  --config.file=$CONFIG_DIR/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=$PROMETHEUS_DIR/consoles \
  --web.console.libraries=$PROMETHEUS_DIR/console_libraries \
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/prometheus.service /etc/systemd/system/
sudo mkdir -p /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

# Make sure the binary is executable
sudo chmod +x $PROMETHEUS_DIR/prometheus
sudo chmod +x $PROMETHEUS_DIR/promtool

# Start prometheus service
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

echo "Prometheus installation completed and service started"
echo "Prometheus is configured to scrape Kyuubi metrics from localhost:10019"
echo "Metrics are being sent to AWS Managed Prometheus workspace: $WORKSPACE_ID"