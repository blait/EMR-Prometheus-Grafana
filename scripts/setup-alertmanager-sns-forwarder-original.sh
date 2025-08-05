#!/bin/bash -xe

#install SNS Forwarder
sudo useradd --no-create-home --shell /bin/false sns-forwarder
sudo mkdir -p /etc/sns-forwarder/conf
sudo mkdir /var/lib/sns-forwarder
sudo chown -R sns-forwarder:sns-forwarder /etc/sns-forwarder
sudo chown sns-forwarder:sns-forwarder /var/lib/sns-forwarder
cd /tmp
wget https://odp-hyeonsup-meterials.s3.amazonaws.com/emr-monitoring/config/alertmanager-sns-forwarder/alertmanager-sns-forwarder
sudo chmod +x alertmanager-sns-forwarder
sudo cp alertmanager-sns-forwarder /usr/local/bin/
sudo chown sns-forwarder:sns-forwarder /usr/local/bin/alertmanager-sns-forwarder

#configure SNS Forwarder as a service
wget https://odp-hyeonsup-meterials.s3.amazonaws.com/emr-monitoring/config/alertmanager-sns-forwarder/default.tmpl
sudo cp default.tmpl /etc/sns-forwarder/conf/default.tmpl
sudo chown sns-forwarder:sns-forwarder /etc/sns-forwarder/conf/default.tmpl

wget https://odp-hyeonsup-meterials.s3.amazonaws.com/emr-monitoring/config/service-files/alertmanager-sns-forwarder.service
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '(?<="accountId" : ")[^"]*(?=")'`
ARN_PREFIX=arn:aws:sns:${EC2_REGION}:${ACCOUNT_ID}:
sudo sed "s/<arn_prefix>/${ARN_PREFIX}/g" alertmanager-sns-forwarder.service | sudo tee /etc/systemd/system/alertmanager-sns-forwarder.service

sudo chown sns-forwarder:sns-forwarder /etc/systemd/system/alertmanager-sns-forwarder.service
sudo systemctl daemon-reload
sudo systemctl start alertmanager-sns-forwarder
sudo systemctl status alertmanager-sns-forwarder
sudo systemctl enable alertmanager-sns-forwarder