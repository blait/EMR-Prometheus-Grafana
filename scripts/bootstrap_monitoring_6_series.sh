#!/bin/bash -xe

#set up node_exporter for pushing OS level metrics
sudo useradd --no-create-home --shell /bin/false node_exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.0.0/node_exporter-1.0.0.linux-amd64.tar.gz
tar -xvzf node_exporter-1.0.0.linux-amd64.tar.gz
cd node_exporter-1.0.0.linux-amd64
sudo cp node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

cd /tmp
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/service_files/node_exporter.service
sudo cp node_exporter.service /etc/systemd/system/node_exporter.service
sudo chown node_exporter:node_exporter /etc/systemd/system/node_exporter.service
sudo systemctl daemon-reload && \
sudo systemctl start node_exporter && \
sudo systemctl status node_exporter && \
sudo systemctl enable node_exporter

#set up jmx_exporter for pushing application metrics
wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.13.0/jmx_prometheus_javaagent-0.13.0.jar
sudo mkdir /etc/prometheus
sudo cp jmx_prometheus_javaagent-0.13.0.jar /etc/prometheus

wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/jmx_exporter_yaml/hdfs_jmx_config_namenode.yaml
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/jmx_exporter_yaml/hdfs_jmx_config_datanode.yaml
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/jmx_exporter_yaml/yarn_jmx_config_resource_manager.yaml
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/jmx_exporter_yaml/yarn_jmx_config_node_manager.yaml

HADOOP_CONF='/etc/hadoop/conf.empty'
sudo mkdir -p ${HADOOP_CONF}
sudo cp hdfs_jmx_config_namenode.yaml ${HADOOP_CONF}
sudo cp hdfs_jmx_config_datanode.yaml ${HADOOP_CONF}
sudo cp yarn_jmx_config_resource_manager.yaml ${HADOOP_CONF}
sudo cp yarn_jmx_config_node_manager.yaml ${HADOOP_CONF}

#set up after_provision_action.sh script to be executed after applications are provisioned. This is needed so as to set up jmx exporter for some applications.
wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/scripts/after_provision_action.sh
sudo chmod +x /tmp/after_provision_action.sh
sudo sed 's/null &/null \&\& \/tmp\/after_provision_action.sh >> $STDOUT_LOG 2>> $STDERR_LOG \&\n/' /usr/share/aws/emr/node-provisioner/bin/provision-node > /tmp/provision-node.new
sudo cp /tmp/provision-node.new /usr/share/aws/emr/node-provisioner/bin/provision-node

exit 0