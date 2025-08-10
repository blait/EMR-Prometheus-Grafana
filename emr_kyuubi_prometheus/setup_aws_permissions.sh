#!/bin/bash

# Script to set up necessary AWS permissions for Prometheus to write to AWS Managed Prometheus

set -e

WORKSPACE_ID="demo-emr"
CLUSTER_NAME="midp-batch-cluster-2"
ROLE_NAME=$(aws emr describe-cluster --cluster-id $CLUSTER_NAME --query Cluster.ServiceRole --output text)

echo "Setting up AWS permissions for EMR cluster $CLUSTER_NAME to write to Prometheus workspace $WORKSPACE_ID..."

# Create policy document
cat > /tmp/amp-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "aps:RemoteWrite",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
        "aps:GetSeries",
        "aps:QueryMetrics"
      ],
      "Resource": "arn:aws:aps:*:*:workspace/${WORKSPACE_ID}"
    }
  ]
}
EOF

# Create policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name EMRPrometheusRemoteWritePolicy \
  --policy-document file:///tmp/amp-policy.json \
  --query 'Policy.Arn' \
  --output text)

# Attach policy to EMR role
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

echo "AWS permissions setup completed. EMR cluster can now write to AWS Managed Prometheus workspace."