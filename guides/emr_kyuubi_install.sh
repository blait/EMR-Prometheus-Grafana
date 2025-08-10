#!/bin/bash

# EMR on EC2 Kyuubi Installation Script
# This script installs Apache Kyuubi on an EMR cluster

set -e

# Configuration variables
KYUUBI_VERSION="1.10.2"
SPARK_VERSION="3.5.5" # EMR 7.9.0
HADOOP_VERSION="3"
KYUUBI_HOME="/opt/kyuubi"
KYUUBI_WORK_DIR="/opt/kyuubi/work"
KYUUBI_LOG_DIR="/var/log/kyuubi"
KYUUBI_PID_DIR="/var/run/kyuubi"
KYUUBI_CONF_DIR="/opt/kyuubi/conf"

echo "Starting Kyuubi installation on EMR..."

# Create necessary directories
sudo mkdir -p $KYUUBI_HOME
sudo mkdir -p $KYUUBI_WORK_DIR
sudo mkdir -p $KYUUBI_LOG_DIR
sudo mkdir -p $KYUUBI_PID_DIR
sudo mkdir -p $KYUUBI_CONF_DIR

# Download Kyuubi
KYUUBI_PACKAGE="apache-kyuubi-${KYUUBI_VERSION}-bin"
DOWNLOAD_URL="https://downloads.apache.org/kyuubi/kyuubi-${KYUUBI_VERSION}/${KYUUBI_PACKAGE}.tgz"

echo "Downloading Kyuubi from $DOWNLOAD_URL"
wget -q $DOWNLOAD_URL -O /tmp/kyuubi.tgz

# Extract Kyuubi
echo "Extracting Kyuubi package..."
sudo tar -xzf /tmp/kyuubi.tgz -C /tmp
sudo cp -r /tmp/${KYUUBI_PACKAGE}/* $KYUUBI_HOME/
sudo rm -f /tmp/kyuubi.tgz

# Configure Kyuubi
echo "Configuring Kyuubi..."
# Copy the template file and modify it
sudo cp $KYUUBI_HOME/conf/kyuubi-env.sh.template $KYUUBI_CONF_DIR/kyuubi-env.sh

# Add environment variables to kyuubi-env.sh
sudo tee -a $KYUUBI_CONF_DIR/kyuubi-env.sh > /dev/null << EOF

# EMR specific configurations
export JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \$(which java))))
export SPARK_HOME=/usr/lib/spark
export SPARK_CONF_DIR=/usr/lib/spark/conf
export HADOOP_HOME=/usr/lib/hadoop
export HADOOP_CONF_DIR=/etc/hadoop/conf
export KYUUBI_HOME=$KYUUBI_HOME
export KYUUBI_WORK_DIR=$KYUUBI_WORK_DIR
export KYUUBI_LOG_DIR=$KYUUBI_LOG_DIR
export KYUUBI_PID_DIR=$KYUUBI_PID_DIR
export KYUUBI_CONF_DIR=$KYUUBI_CONF_DIR
EOF

sudo chmod +x $KYUUBI_CONF_DIR/kyuubi-env.sh

# Create kyuubi-defaults.conf from template
sudo cp $KYUUBI_HOME/conf/kyuubi-defaults.conf.template $KYUUBI_CONF_DIR/kyuubi-defaults.conf

# Add custom configurations
sudo tee -a $KYUUBI_CONF_DIR/kyuubi-defaults.conf > /dev/null << EOF

# Custom configurations
kyuubi.metrics.reporters=PROMETHEUS
kyuubi.frontend.thrift.binary.bind.host=0.0.0.0
kyuubi.frontend.thrift.binary.bind.port=10009
kyuubi.frontend.rest.bind.host=0.0.0.0
kyuubi.frontend.rest.bind.port=10099
kyuubi.engine.share.level=CONNECTION
kyuubi.engine.type=SPARK_SQL
kyuubi.engine.pool.size=1
kyuubi.engine.pool.size.threshold=32

# Zookeeper
kyuubi.ha.zookeeper.quorum=localhost:2181
kyuubi.ha.zookeeper.namespace=kyuubi
# kyuubi.ha.addresses=localhost:2182
# kyuubi.ha.embedded.zk.port=2182

EOF

# Set permissions
echo "Setting permissions..."
sudo chown -R hadoop:hadoop $KYUUBI_HOME
sudo chown -R hadoop:hadoop $KYUUBI_WORK_DIR
sudo chown -R hadoop:hadoop $KYUUBI_LOG_DIR
sudo chown -R hadoop:hadoop $KYUUBI_PID_DIR

# Ensure directories are accessible
sudo chmod 755 $KYUUBI_HOME
sudo chmod 755 $KYUUBI_WORK_DIR
sudo chmod 755 $KYUUBI_LOG_DIR
sudo chmod 755 $KYUUBI_PID_DIR

# Test Kyuubi start manually first
echo "Testing Kyuubi start manually..."
sudo -u hadoop $KYUUBI_HOME/bin/kyuubi start

# Wait for Kyuubi to start
sleep 10

# Check if Kyuubi started successfully
if [ -f "$KYUUBI_PID_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.pid" ]; then
  echo "Kyuubi started successfully in manual test. Proceeding with systemd service setup."
  sudo -u hadoop $KYUUBI_HOME/bin/kyuubi stop
  sleep 5
else
  echo "Manual Kyuubi start failed. Checking logs..."
  if [ -f "$KYUUBI_LOG_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.out" ]; then
    echo "Last 20 lines of Kyuubi log:"
    tail -n 20 "$KYUUBI_LOG_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.out"
  fi
  echo "Please check logs at $KYUUBI_LOG_DIR for more details."
  echo "Continuing with systemd setup anyway..."
fi

# Create systemd service file
echo "Creating systemd service for Kyuubi..."
cat > /tmp/kyuubi.service << EOF
[Unit]
Description=Apache Kyuubi Server
After=network.target

[Service]
Type=forking
User=hadoop
Group=hadoop
Environment="JAVA_HOME=/etc/alternatives/jre"
ExecStart=$KYUUBI_HOME/bin/kyuubi start
ExecStop=$KYUUBI_HOME/bin/kyuubi stop
Restart=on-failure
PIDFile=$KYUUBI_PID_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.pid
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/kyuubi.service /etc/systemd/system/
sudo systemctl daemon-reload

# Start Kyuubi service
echo "Starting Kyuubi service..."
sudo systemctl start kyuubi

# Check service status
echo "Checking Kyuubi service status..."
sleep 10
if sudo systemctl is-active --quiet kyuubi; then
  echo "Kyuubi service started successfully!"
  sudo systemctl enable kyuubi
  echo "Kyuubi server is running on port 10009 (Thrift) and 10099 (REST)"
else
  echo "Kyuubi service failed to start. Checking status and logs..."
  sudo systemctl status kyuubi
  echo -e "\nJournal logs:"
  sudo journalctl -xeu kyuubi.service --no-pager | tail -n 30
  
  echo -e "\nKyuubi logs:"
  if [ -f "$KYUUBI_LOG_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.out" ]; then
    tail -n 30 "$KYUUBI_LOG_DIR/kyuubi-hadoop-org.apache.kyuubi.server.KyuubiServer.out"
  fi
  
  echo -e "\nTrying to start Kyuubi manually to see if it works..."
  sudo -u hadoop $KYUUBI_HOME/bin/kyuubi start
  
  echo "Installation completed with errors. Please check the logs for details."
  exit 1
fi

# Add Kyuubi to PATH for all users
echo "Adding Kyuubi to PATH..."
sudo tee /etc/profile.d/kyuubi.sh > /dev/null << EOF
export PATH=\$PATH:$KYUUBI_HOME/bin
EOF

echo "Installation complete!"