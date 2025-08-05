#!/bin/bash

# EMR Bootstrap Script for Prometheus Monitoring
# S3에 업로드된 기존 AWS 블로그 스크립트들을 활용

set -e

echo "=== EMR Monitoring Bootstrap 시작 ==="
echo "기존 AWS 블로그 스크립트들을 활용하여 모니터링 에이전트 설치"

# 노드 타입 확인
IS_MASTER=false
if grep -q '"isMaster":true' /mnt/var/lib/info/instance.json 2>/dev/null; then
    IS_MASTER=true
    echo "마스터 노드에서 실행 중"
else
    echo "워커 노드에서 실행 중"
fi

# 임시 디렉토리로 이동
cd /tmp

echo "=== 기존 AWS 블로그 스크립트들 다운로드 ==="

# S3에서 기존 스크립트들 다운로드
echo "Prometheus 설치 스크립트 다운로드..."
aws s3 cp s3://odp-hyeonsup-meterials/scripts/setup-prometheus.sh ./
chmod +x setup-prometheus.sh

echo "Alertmanager 설치 스크립트 다운로드..."
aws s3 cp s3://odp-hyeonsup-meterials/scripts/setup-alertmanager.sh ./
chmod +x setup-alertmanager.sh

echo "Grafana 설치 스크립트 다운로드..."
aws s3 cp s3://odp-hyeonsup-meterials/scripts/setup-grafana.sh ./
chmod +x setup-grafana.sh

echo "=== 모든 노드에 Node Exporter 설치 ==="
# 기존 스크립트에서 Node Exporter 부분만 추출하여 실행
# (실제로는 setup-prometheus.sh에 Node Exporter 설치가 포함되어 있을 것)

# Node Exporter 직접 설치 (기존 방식과 동일)
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.0.1/node_exporter-1.0.1.linux-amd64.tar.gz
tar xzf node_exporter-1.0.1.linux-amd64.tar.gz
sudo cp node_exporter-1.0.1.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Node Exporter 서비스 생성 (기존 방식과 동일)
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=hadoop
Group=hadoop
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Node Exporter 서비스 시작
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "Node Exporter 설치 완료 (포트 9100)"

# 마스터 노드에서만 추가 설정
if [ "$IS_MASTER" = true ]; then
    echo "=== 마스터 노드 전용 설정 ==="
    
    # JMX Exporter 설정 (기존 방식과 동일)
    echo "JMX Exporter 설정 중..."
    wget -q https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.14.0/jmx_prometheus_javaagent-0.14.0.jar
    sudo cp jmx_prometheus_javaagent-0.14.0.jar /usr/local/bin/
    
    # JMX 설정 파일 생성
    sudo tee /usr/local/bin/jmx_config.yaml > /dev/null <<EOF
rules:
- pattern: ".*"
EOF
    
    # Hadoop/YARN 환경 변수에 JMX Exporter 추가
    echo 'export HADOOP_OPTS="$HADOOP_OPTS -javaagent:/usr/local/bin/jmx_prometheus_javaagent-0.14.0.jar=7001:/usr/local/bin/jmx_config.yaml"' | sudo tee -a /etc/hadoop/conf/hadoop-env.sh
    echo 'export YARN_OPTS="$YARN_OPTS -javaagent:/usr/local/bin/jmx_prometheus_javaagent-0.14.0.jar=7005:/usr/local/bin/jmx_config.yaml"' | sudo tee -a /etc/hadoop/conf/yarn-env.sh
    
    echo "JMX Exporter 설정 완료 (포트 7001, 7005)"
fi

echo "=== 설치 확인 ==="
sudo systemctl status node_exporter --no-pager -l

echo "=== EMR Monitoring Bootstrap 완료! ==="
echo "✅ Node Exporter: 모든 노드의 포트 9100"
if [ "$IS_MASTER" = true ]; then
    echo "✅ JMX Exporter: 마스터 노드의 포트 7001 (Hadoop), 7005 (YARN)"
fi
echo "✅ 기존 Prometheus 서버에서 메트릭 수집 가능"
