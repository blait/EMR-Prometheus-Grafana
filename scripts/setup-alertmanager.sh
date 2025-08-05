#!/bin/bash -xe

#install Alertmanager
sudo useradd --no-create-home --shell /bin/false alertmanager
sudo mkdir -p /etc/alertmanager/conf
sudo mkdir /var/lib/alertmanager
sudo chown -R alertmanager:alertmanager /etc/alertmanager
sudo chown alertmanager:alertmanager /var/lib/alertmanager
cd /tmp
wget https://github.com/prometheus/alertmanager/releases/download/v0.21.0/alertmanager-0.21.0.linux-amd64.tar.gz
tar xvf alertmanager-0.21.0.linux-amd64.tar.gz
cd alertmanager-0.21.0.linux-amd64
sudo cp alertmanager /usr/local/bin/
sudo cp amtool /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager
sudo chown alertmanager:alertmanager /usr/local/bin/amtool

#configure Alertmanager as a service
cd /tmp
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/alertmanager/alertmanager.yml
sudo cp alertmanager.yml /etc/alertmanager/conf/alertmanager.yml
sudo chown alertmanager:alertmanager /etc/alertmanager/conf/alertmanager.yml

wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/service_files/alertmanager.service
sudo cp alertmanager.service /etc/systemd/system/alertmanager.service
sudo chown alertmanager:alertmanager /etc/systemd/system/alertmanager.service
sudo systemctl daemon-reload
sudo systemctl start alertmanager
sudo systemctl status alertmanager
sudo systemctl enable alertmanager