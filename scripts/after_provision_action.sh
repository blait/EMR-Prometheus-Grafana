#!/bin/bash -xe

# Find applications installed
APPLICATIONS_INSTALLED=$(CLUSTER_ID=$(cat /mnt/var/lib/info/extraInstanceData.json | jq -r ".jobFlowId"); REGION=$(cat /mnt/var/lib/info/extraInstanceData.json | jq -r ".region"); aws emr describe-cluster --cluster-id $CLUSTER_ID --region $REGION | jq -r ".Cluster.Applications[].Name")

IS_MASTER=$(cat /mnt/var/lib/info/instance.json | jq -r ".isMaster" | grep "true" || true);

IS_HADOOP_INSTALLED=$(echo "${APPLICATIONS_INSTALLED}" | grep "Hadoop" || true);

if [ ! -z $IS_HADOOP_INSTALLED ]; then
  cd /tmp;
  wget https://aws-bigdata-blog.s3.amazonaws.com/artifacts/aws-blog-emr-prometheus-grafana/scripts/yarn_jmx_env_setup.txt;
  cat /tmp/yarn_jmx_env_setup.txt | sudo tee -a /etc/hadoop/conf/yarn-env.sh > /dev/null;
  if [ ! -z $IS_MASTER ]; then
    sudo systemctl restart hadoop-yarn-resourcemanager.service;
  else
    sudo systemctl restart hadoop-yarn-nodemanager.service;
  fi;
fi;