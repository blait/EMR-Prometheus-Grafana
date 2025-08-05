#!/bin/bash -xe

#install Grafana
cd /tmp
wget https://dl.grafana.com/oss/release/grafana-7.1.1-1.x86_64.rpm
sudo yum -y install grafana-7.1.1-1.x86_64.rpm

wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/grafana/grafana_prometheus_datasource.yaml
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo cp /tmp/grafana_prometheus_datasource.yaml /etc/grafana/provisioning/datasources/prometheus.yaml

wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/grafana/grafana_dashboard.yaml
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo cp /tmp/grafana_dashboard.yaml /etc/grafana/provisioning/dashboards/default.yaml

sudo mkdir -p /var/lib/grafana/dashboards
cd /var/lib/grafana/dashboards

wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/HDFS+-+DataNode.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/HDFS+-+NameNode.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/JVM+Metrics.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/Log+Metrics.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/OS+Level+Metrics.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/RPC+Metrics.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/YARN+-+Node+Manager.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/YARN+-+Queues.json
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/dashboards/YARN+-+Resource+Manager.json
sudo chown -R grafana:grafana /var/lib/grafana

#configure Grafana as a service
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl status grafana-server
sudo systemctl enable grafana-server