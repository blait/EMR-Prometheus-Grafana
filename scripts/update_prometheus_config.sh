#!/bin/bash
# Update Prometheus configuration to include Spark Application Exporter

echo "=== Updating Prometheus Configuration ==="

# Backup current config
sudo cp /etc/prometheus/conf/prometheus.yml /etc/prometheus/conf/prometheus.yml.backup.$(date +%Y%m%d_%H%M%S)

# Add Spark Application Exporter job
sudo tee -a /etc/prometheus/conf/prometheus.yml > /dev/null <<EOF

  # Spark Application Metrics Exporter
  - job_name: 'spark-applications'
    static_configs:
      - targets: ['localhost:8081']
        labels:
          service: 'spark-app-exporter'
    scrape_interval: 30s
    metrics_path: /metrics
EOF

echo "Updated Prometheus configuration"

# Validate configuration
echo "Validating Prometheus configuration..."
if sudo /usr/local/bin/promtool check config /etc/prometheus/conf/prometheus.yml; then
    echo "✅ Configuration is valid"
    
    # Reload Prometheus
    echo "Reloading Prometheus..."
    sudo systemctl reload prometheus
    
    echo "✅ Prometheus reloaded successfully"
    echo ""
    echo "New metrics will be available at:"
    echo "- spark_application_memory_used_mb"
    echo "- spark_application_vcores_used"
    echo "- spark_executor_memory_used_mb"
    echo "- spark_executor_cores_total"
    echo "And many more..."
else
    echo "❌ Configuration validation failed"
    echo "Restoring backup..."
    sudo cp /etc/prometheus/conf/prometheus.yml.backup.$(date +%Y%m%d_%H%M%S) /etc/prometheus/conf/prometheus.yml
    exit 1
fi
