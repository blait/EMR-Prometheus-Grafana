# Apache Kyuubi 모니터링 추가 가이드

기존 CloudFormation으로 배포된 EMR 모니터링 시스템에 Apache Kyuubi 메트릭을 추가하는 가이드입니다.

## 📋 전제 조건

- CloudFormation으로 배포된 EMR 모니터링 시스템이 정상 동작 중
- Grafana 대시보드가 정상적으로 표시되고 있음
- EMR 클러스터가 실행 중

## 🚀 단계별 설정

### 1단계: EMR 클러스터 정보 확인

기존 모니터링 시스템에서 EMR 클러스터 정보를 확인합니다:

```bash
# CloudFormation 스택에서 EMR 클러스터 ID 확인
EMR_CLUSTER_ID=$(aws cloudformation describe-stacks \
  --stack-name emr-monitoring-complete \
  --query 'Stacks[0].Outputs[?OutputKey==`EMRClusterID`].OutputValue' \
  --output text)

# EMR 마스터 노드 DNS 확인
EMR_MASTER_DNS=$(aws emr describe-cluster --cluster-id $EMR_CLUSTER_ID \
  --query 'Cluster.MasterPublicDnsName' --output text)

# Prometheus 서버 IP 확인
PROMETHEUS_SERVER_IP=$(aws cloudformation describe-stacks \
  --stack-name emr-monitoring-complete \
  --query 'Stacks[0].Outputs[?OutputKey==`PrometheusServerPublicIP`].OutputValue' \
  --output text)

echo "EMR 클러스터 ID: $EMR_CLUSTER_ID"
echo "EMR 마스터 DNS: $EMR_MASTER_DNS"
echo "Prometheus 서버 IP: $PROMETHEUS_SERVER_IP"
```

### 2단계: Kyuubi 설치

EMR 마스터 노드에 Kyuubi를 설치합니다:

```bash
# 1. 설치 스크립트 복사
scp -i your-key.pem guides/emr_kyuubi_install.sh hadoop@$EMR_MASTER_DNS:/tmp/

# 2. EMR에서 스크립트 실행
ssh -i your-key.pem hadoop@$EMR_MASTER_DNS "
chmod +x /tmp/emr_kyuubi_install.sh
sudo /tmp/emr_kyuubi_install.sh
"

# 3. 설치 확인
ssh -i your-key.pem hadoop@$EMR_MASTER_DNS "
sudo systemctl status kyuubi --no-pager
curl -s http://localhost:10019/metrics | head -5
"
```

### 3단계: EMR ZooKeeper 서비스 활성화

**⚠️ 중요**: Kyuubi 안정적 실행을 위해 EMR의 기본 ZooKeeper 서비스를 활성화해야 합니다.

```bash
# EMR 마스터 노드에서 실행
ssh -i your-key.pem hadoop@$EMR_MASTER_DNS

# ZooKeeper 설정 파일 생성
sudo mkdir -p /emr/instance-controller/lib/zookeeper/conf
sudo tee /emr/instance-controller/lib/zookeeper/conf/ic-zookeeper-quorum.cfg << 'EOF'
tickTime=2000
dataDir=/var/lib/zookeeper
clientPort=2181
initLimit=5
syncLimit=2
server.1=localhost:2888:3888
EOF

# 데이터 디렉토리 설정
sudo mkdir -p /var/lib/zookeeper
sudo chown hadoop:hadoop /var/lib/zookeeper
echo '1' | sudo tee /var/lib/zookeeper/myid

# EMR ZooKeeper 서비스 시작
sudo service ic-zookeeper-quorum start

# 상태 확인
echo 'ruok' | nc localhost 2181
# 응답: imok (정상)

# Kyuubi 재시작 (ZooKeeper 연결 적용)
sudo systemctl restart kyuubi
sudo systemctl status kyuubi --no-pager
```

### 4단계: 보안 그룹 설정

Prometheus가 Kyuubi 메트릭을 수집할 수 있도록 보안 그룹을 설정합니다:

```bash
# EMR 마스터 보안 그룹 ID 확인
EMR_MASTER_SG=$(aws emr describe-cluster --cluster-id $EMR_CLUSTER_ID \
  --query 'Cluster.Ec2InstanceAttributes.EmrManagedMasterSecurityGroup' --output text)

# Prometheus 서버 보안 그룹 ID 확인
PROMETHEUS_SG=$(aws ec2 describe-instances \
  --filters "Name=ip-address,Values=$PROMETHEUS_SERVER_IP" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# EMR 마스터에서 Prometheus로의 10019 포트 허용
aws ec2 authorize-security-group-ingress \
  --group-id $EMR_MASTER_SG \
  --protocol tcp \
  --port 10019 \
  --source-group $PROMETHEUS_SG || echo "Rule may already exist"

echo "✅ 보안 그룹 설정 완료"
```

### 5단계: Prometheus 서버 설정 업데이트

Prometheus 설정에 Kyuubi 타겟을 추가합니다:

```bash
# Prometheus 서버에 접속하여 설정 업데이트
ssh -i your-key.pem ec2-user@$PROMETHEUS_SERVER_IP "
# 기존 설정 백업
sudo cp /etc/prometheus/conf/prometheus.yml /etc/prometheus/conf/prometheus.yml.backup

# Kyuubi job 추가
sudo tee -a /etc/prometheus/conf/prometheus.yml << EOF

  # Kyuubi Metrics
  - job_name: 'kyuubi'
    static_configs:
      - targets: ['$EMR_MASTER_DNS:10019']
        labels:
          cluster_id: '$EMR_CLUSTER_ID'
          service: 'kyuubi'
EOF

# Prometheus 재시작
sudo systemctl restart prometheus
sudo systemctl status prometheus --no-pager
"

# 설정 확인
curl -s "http://$PROMETHEUS_SERVER_IP:9090/api/v1/targets" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
kyuubi_targets = [t for t in data['data']['activeTargets'] if t['labels'].get('job') == 'kyuubi']
if kyuubi_targets:
    print('✅ Kyuubi 타겟 추가됨')
    for target in kyuubi_targets:
        print(f'  - {target[\"scrapeUrl\"]} ({target[\"health\"]})')
else:
    print('❌ Kyuubi 타겟 없음')
"
```

### 6단계: Grafana 대시보드 추가

Grafana에서 Kyuubi 대시보드를 추가합니다:

```bash
# 1. 수정된 Kyuubi 대시보드 파일 복사 (모든 호환성 문제 해결됨)
scp -i your-key.pem config/grafana-dashboards/Kyuubi-Dashboard.json ec2-user@$PROMETHEUS_SERVER_IP:/tmp/

# 2. Prometheus 서버에서 대시보드 설치
ssh -i your-key.pem ec2-user@$PROMETHEUS_SERVER_IP "
sudo cp /tmp/Kyuubi-Dashboard.json /var/lib/grafana/dashboards/
sudo chown grafana:grafana /var/lib/grafana/dashboards/Kyuubi-Dashboard.json
sudo systemctl restart grafana-server
"
```

**📊 완성된 대시보드 구성 (22개 데이터 패널):**

#### **System Overview**
- JVM Uptime, Total Connections, Total Operations, Total Engines

#### **Connections & Sessions** 
- Open Connections, Connection Rate (5m)

#### **Operations Status**
- Open Operations, Operation States, Statement Execution Time, Max Pending Time

#### **JVM Memory Usage**
- Heap Memory Usage, Non-Heap Memory Usage, Memory Usage Ratio, Buffer Pool Usage

#### **Threads & GC Status**
- Thread Counts, Thread States, GC Count, GC Time

#### **REST API Monitoring**
- REST API Requests, Response Codes, Error Rates, REST Connections

### 7단계: 모니터링 확인

모든 설정이 완료되었는지 확인합니다:

```bash
# 1. Kyuubi 서비스 상태 확인
ssh -i your-key.pem hadoop@$EMR_MASTER_DNS "
echo '=== Kyuubi 모니터링 완전성 검증 ==='
echo '1. ZooKeeper:' \$(echo 'ruok' | nc localhost 2181 2>/dev/null || echo 'Not running')
echo '2. Kyuubi:' \$(systemctl is-active kyuubi)
echo '3. 메트릭 수:' \$(curl -s http://localhost:10019/metrics | grep '^kyuubi_' | wc -l)'개'
echo '4. JVM Uptime:' \$(curl -s http://localhost:10019/metrics | grep kyuubi_jvm_uptime | awk '{print \$2}')'초'
"

# 2. Prometheus에서 메트릭 수집 확인
curl -s "http://$PROMETHEUS_SERVER_IP:9090/api/v1/query?query=kyuubi_jvm_uptime" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['status'] == 'success' and data['data']['result']:
    print('✅ Prometheus에서 Kyuubi 메트릭 수집 중')
    print(f'JVM Uptime: {data[\"data\"][\"result\"][0][\"value\"][1]}초')
else:
    print('❌ Prometheus에서 Kyuubi 메트릭 수집 실패')
"

# 3. Grafana 대시보드 접근
echo "📊 Grafana 대시보드 URL:"
echo "http://$PROMETHEUS_SERVER_IP:3000"
echo "로그인: admin/admin"
echo "대시보드: Kyuubi Dashboard"
```

## 🔍 트러블슈팅

### **문제 1: JVM Uptime이 계속 감소하거나 불규칙**
**원인**: Kyuubi가 ZooKeeper 연결 실패로 재시작 반복  
**해결**: 3단계 ZooKeeper 활성화 확인

### **문제 2: Prometheus가 Kyuubi 메트릭 수집 실패**
**원인**: 보안 그룹에서 10019 포트 차단  
**해결**: 4단계 보안 그룹 설정 확인

### **문제 3: 대시보드에 "Test data" 또는 패널 오류**
**원인**: 호환성 문제  
**해결**: 제공된 수정된 대시보드 파일 사용 (모든 문제 해결됨)

## ✅ 완료

이제 기존 EMR 모니터링 시스템에 Kyuubi 메트릭이 추가되어 다음을 모니터링할 수 있습니다:

- **Kyuubi 서버 상태**: JVM, 메모리, 스레드
- **연결 관리**: 클라이언트 연결 상태 및 활동
- **작업 처리**: SQL 작업 실행 상태 및 성능
- **시스템 리소스**: GC 활동, API 응답 상태

Grafana에서 실시간으로 Kyuubi 성능을 모니터링하고 문제를 사전에 감지할 수 있습니다.
