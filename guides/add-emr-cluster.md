# 📋 기존 모니터링 시스템에 새 EMR 클러스터 추가 가이드

## 개요
기존 Prometheus/Grafana 모니터링 시스템을 유지하면서, Spark가 포함된 새 EMR 클러스터를 추가하고 모니터링 연동하는 가이드입니다.

---

## 🎯 전제 조건

- ✅ 기존 EMR 모니터링 시스템이 CloudFormation으로 배포되어 운영 중
- ✅ 기존 Prometheus/Grafana/Alertmanager 정상 동작 중
- ✅ AWS CLI 설정 완료 및 적절한 IAM 권한 보유
- ✅ 기존 시스템과 동일한 VPC/서브넷 사용 예정

---

## 🔍 1단계: 기존 시스템 정보 확인

### 1.1 기존 CloudFormation 스택 파라미터 확인
```bash
# 기존 스택 이름 확인 (예: emr-sktMonitor)
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `emr`) || contains(StackName, `monitor`)].StackName' \
  --output table

# 스택 파라미터 확인
STACK_NAME="emr-sktMonitor"  # 실제 스택 이름으로 변경
aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query 'Stacks[0].Parameters' --output table
```

### 1.2 필요한 정보 추출
```bash
# VPC ID 확인
VPC_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query 'Stacks[0].Parameters[?ParameterKey==`VPC`].ParameterValue' --output text)

# 서브넷 ID 확인
SUBNET_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query 'Stacks[0].Parameters[?ParameterKey==`Subnet`].ParameterValue' --output text)

# 키페어 이름 확인
KEY_NAME=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query 'Stacks[0].Parameters[?ParameterKey==`EMRKeyName`].ParameterValue' --output text)

# Prometheus 서버 보안 그룹 ID 확인
PROMETHEUS_SG=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id PrometheusServerSecurityGroup \
  --query 'StackResources[0].PhysicalResourceId' --output text)

echo "=== 기존 시스템 정보 ==="
echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID" 
echo "Key Name: $KEY_NAME"
echo "Prometheus SG: $PROMETHEUS_SG"
```

### 1.3 기존 Prometheus 서버 IP 확인
```bash
# Prometheus 서버 퍼블릭 IP 확인
PROMETHEUS_IP=$(aws cloudformation describe-stacks --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' --output text | \
  sed 's/http:\/\/\([^:]*\):.*/\1/')

echo "Prometheus 서버 IP: $PROMETHEUS_IP"
```

---

## 🚀 2단계: 새 EMR 클러스터 생성

### 2.1 EMR 클러스터 생성 명령어
```bash
# 새 EMR 클러스터 생성 (Hadoop + Spark 포함)
NEW_CLUSTER_ID=$(aws emr create-cluster \
  --name "EMR-Spark-Monitoring-Additional" \
  --release-label emr-6.0.0 \
  --applications Name=Hadoop Name=Spark \
  --instance-groups \
    InstanceGroupType=MASTER,InstanceCount=1,InstanceType=m5.xlarge \
    InstanceGroupType=CORE,InstanceCount=2,InstanceType=m5.xlarge \
  --bootstrap-actions \
    Path=s3://odp-hyeonsup-meterials/emr-monitoring/scripts/bootstrap_monitoring_6_series.sh,Name="Configure monitoring" \
  --configurations '[
    {
      "Classification": "hadoop-env",
      "Configurations": [
        {
          "Classification": "export",
          "Properties": {
            "HADOOP_NAMENODE_OPTS": "-javaagent:/etc/prometheus/jmx_prometheus_javaagent-0.13.0.jar=7001:/etc/hadoop/conf/hdfs_jmx_config_namenode.yaml -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.port=50103",
            "HADOOP_DATANODE_OPTS": "-javaagent:/etc/prometheus/jmx_prometheus_javaagent-0.13.0.jar=7001:/etc/hadoop/conf/hdfs_jmx_config_datanode.yaml -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.port=50103"
          }
        }
      ]
    }
  ]' \
  --ec2-attributes KeyName=$KEY_NAME,SubnetId=$SUBNET_ID \
  --service-role EMR_DefaultRole \
  --ec2-attributes InstanceProfile=EMR_EC2_DefaultRole \
  --enable-debugging \
  --log-uri s3://odp-hyeonsup-meterials/emr-logs/ \
  --tags Key=Name,Value="EMR Spark cluster for monitoring" Key=application,Value="hadoop-spark" \
  --region us-east-1 \
  --query 'ClusterId' --output text)

echo "새 클러스터 ID: $NEW_CLUSTER_ID"
```

### 2.2 클러스터 생성 상태 확인
```bash
# 클러스터 상태 모니터링
echo "클러스터 생성 중... (약 10-15분 소요)"
while true; do
  STATUS=$(aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
    --query 'Cluster.Status.State' --output text)
  echo "현재 상태: $STATUS ($(date))"
  
  if [ "$STATUS" = "WAITING" ]; then
    echo "✅ 클러스터 생성 완료!"
    break
  elif [ "$STATUS" = "TERMINATED" ] || [ "$STATUS" = "TERMINATED_WITH_ERRORS" ]; then
    echo "❌ 클러스터 생성 실패: $STATUS"
    exit 1
  fi
  
  sleep 30
done

# 클러스터 상세 정보 확인
aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.{Name:Name,State:Status.State,MasterDns:MasterPublicDnsName}' \
  --output table
```

---

## 🔒 3단계: 보안 그룹 연동

### 3.1 새 EMR 클러스터 보안 그룹 ID 확인
```bash
# 새 EMR 마스터 보안 그룹 ID
NEW_EMR_MASTER_SG=$(aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.Ec2InstanceAttributes.EmrManagedMasterSecurityGroup' --output text)

# 새 EMR 슬레이브 보안 그룹 ID  
NEW_EMR_SLAVE_SG=$(aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.Ec2InstanceAttributes.EmrManagedSlaveSecurityGroup' --output text)

echo "새 EMR 마스터 SG: $NEW_EMR_MASTER_SG"
echo "새 EMR 슬레이브 SG: $NEW_EMR_SLAVE_SG"
```

### 3.2 Prometheus 서버 접근 허용 규칙 추가
```bash
# 마스터 노드에 Prometheus 접근 허용 (포트 7001, 9100)
echo "마스터 노드 보안 그룹 규칙 추가 중..."
aws ec2 authorize-security-group-ingress \
  --group-id $NEW_EMR_MASTER_SG \
  --protocol tcp --port 7001 --source-group $PROMETHEUS_SG \
  --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id $NEW_EMR_MASTER_SG \
  --protocol tcp --port 9100 --source-group $PROMETHEUS_SG \
  --region us-east-1

# 슬레이브 노드에 Prometheus 접근 허용 (포트 7001, 9100)
echo "슬레이브 노드 보안 그룹 규칙 추가 중..."
aws ec2 authorize-security-group-ingress \
  --group-id $NEW_EMR_SLAVE_SG \
  --protocol tcp --port 7001 --source-group $PROMETHEUS_SG \
  --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id $NEW_EMR_SLAVE_SG \
  --protocol tcp --port 9100 --source-group $PROMETHEUS_SG \
  --region us-east-1

echo "✅ 보안 그룹 규칙 추가 완료"
```

---

## 🔧 4단계: Prometheus 설정 업데이트

### 4.1 새 EMR 클러스터 정보 확인
```bash
# 새 EMR 마스터 노드 DNS 확인
NEW_EMR_MASTER_DNS=$(aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.MasterPublicDnsName' --output text)

# 새 EMR 코어 노드들 DNS 확인
NEW_EMR_CORE_DNS=$(aws emr list-instances --cluster-id $NEW_CLUSTER_ID \
  --instance-group-types CORE \
  --query 'Instances[].PublicDnsName' --output text)

echo "새 EMR 마스터 DNS: $NEW_EMR_MASTER_DNS"
echo "새 EMR 코어 노드 DNS: $NEW_EMR_CORE_DNS"
```

### 4.2 기존 Prometheus 서버 접속 및 설정 업데이트
```bash
# Prometheus 서버에 SSH 접속 (별도 터미널에서 실행)
echo "다음 명령어로 Prometheus 서버에 접속하세요:"
echo "ssh -i [키페어.pem] ec2-user@$PROMETHEUS_IP"
```

### 4.3 Prometheus 설정 파일 업데이트 (Prometheus 서버에서 실행)
```bash
# Prometheus 서버에 SSH 접속 후 실행
sudo cp /etc/prometheus/conf/prometheus.yml /etc/prometheus/conf/prometheus.yml.backup

# 새 EMR 클러스터 타겟 추가
sudo tee -a /etc/prometheus/conf/prometheus.yml > /dev/null <<EOF

  # 새 EMR 클러스터 (Spark 포함) - 마스터 노드
  - job_name: 'emr-spark-master'
    static_configs:
      - targets: ['$NEW_EMR_MASTER_DNS:7001', '$NEW_EMR_MASTER_DNS:9100']
        labels:
          cluster: 'emr-spark-additional'
          node_type: 'master'

  # 새 EMR 클러스터 (Spark 포함) - 코어 노드들
  - job_name: 'emr-spark-core'
    static_configs:
EOF

# 코어 노드들을 동적으로 추가
for core_dns in $NEW_EMR_CORE_DNS; do
sudo tee -a /etc/prometheus/conf/prometheus.yml > /dev/null <<EOF
      - targets: ['${core_dns}:7001', '${core_dns}:9100']
        labels:
          cluster: 'emr-spark-additional'
          node_type: 'core'
EOF
done

# Prometheus 재시작
sudo systemctl restart prometheus
sudo systemctl status prometheus --no-pager -l

echo "✅ Prometheus 설정 업데이트 완료"
```

---

## ✅ 5단계: 연동 확인 및 테스트

### 5.1 Prometheus 타겟 상태 확인
```bash
# Prometheus UI에서 타겟 확인 (브라우저에서 접속)
echo "Prometheus UI: http://$PROMETHEUS_IP:9090/targets"
echo "새 EMR 클러스터 타겟들이 UP 상태인지 확인하세요."

# API로 타겟 상태 확인
curl -s "http://$PROMETHEUS_IP:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.labels.cluster=="emr-spark-additional") | {job: .labels.job, instance: .labels.instance, health: .health}'
```

### 5.2 메트릭 수집 확인
```bash
# 새 클러스터 메트릭 수집 확인
curl -s "http://$PROMETHEUS_IP:9090/api/v1/query?query=up{cluster='emr-spark-additional'}" | \
  jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

# HDFS 메트릭 확인
curl -s "http://$PROMETHEUS_IP:9090/api/v1/query?query=hadoop_namenode_capacitytotal{cluster='emr-spark-additional'}" | \
  jq '.data.result[0].value[1]'
```

### 5.3 Grafana에서 확인
```bash
echo "Grafana UI: http://$PROMETHEUS_IP:3000"
echo "기본 로그인: admin/admin"
echo ""
echo "확인할 대시보드:"
echo "- HDFS - NameNode: 새 클러스터 HDFS 메트릭"
echo "- YARN - Resource Manager: 새 클러스터 YARN 메트릭"
echo "- OS Level Metrics: 새 클러스터 시스템 메트릭"
```

---

## 🧪 6단계: Spark 작업 테스트

### 6.1 새 EMR 마스터 노드 접속
```bash
# 새 EMR 마스터 노드에 SSH 접속
ssh -i [키페어.pem] hadoop@$NEW_EMR_MASTER_DNS
```

### 6.2 Spark 설치 확인 (EMR 마스터 노드에서 실행)
```bash
# Spark 버전 확인
spark-submit --version

# Spark 히스토리 서버 확인
curl -s http://localhost:18080 > /dev/null && echo "✅ Spark History Server 실행 중" || echo "❌ Spark History Server 미실행"

# YARN 애플리케이션 목록 확인
yarn application -list
```

### 6.3 PySpark WordCount 실행
```bash
# PySpark 작업 실행
spark-submit \
  s3://odp-hyeonsup-meterials/emr-monitoring/scripts/wordcount_spark.py \
  s3://aws-bigdata-blog/artifacts/aws-blog-emr-prometheus-grafana/demo/datasets/YelpDataGzip/ \
  s3://odp-hyeonsup-meterials/skt-output/spark-cluster2-output-$(date +%Y%m%d-%H%M%S)

# 작업 상태 모니터링
yarn application -list -appStates RUNNING
```

### 6.4 Grafana에서 Spark 작업 모니터링
```bash
echo "Grafana에서 다음 대시보드들을 확인하세요:"
echo "1. YARN - Resource Manager: Spark 애플리케이션 리소스 사용량"
echo "2. JVM Metrics: Spark 드라이버/익스큐터 JVM 메트릭"
echo "3. OS Level Metrics: 클러스터 노드들의 CPU/메모리 사용량"
echo ""
echo "Spark UI: http://$NEW_EMR_MASTER_DNS:20888 (Spark History Server)"
echo "YARN UI: http://$NEW_EMR_MASTER_DNS:8088 (Resource Manager)"
```

---

## 🎯 완료!

### ✅ 성공적으로 완료된 작업들:

1. **새 EMR 클러스터 생성** - Hadoop + Spark 포함
2. **모니터링 에이전트 설치** - Bootstrap으로 자동 설치
3. **보안 그룹 연동** - 기존 Prometheus 접근 허용
4. **Prometheus 설정 업데이트** - 새 타겟 추가
5. **연동 확인** - 메트릭 수집 및 대시보드 확인
6. **Spark 작업 테스트** - PySpark WordCount 실행

### 🎉 결과:
- **기존 모니터링 시스템 유지** - 기존 EMR 클러스터 모니터링 지속
- **새 EMR 클러스터 추가** - Spark 포함된 추가 클러스터 모니터링
- **통합 모니터링** - 하나의 Prometheus/Grafana에서 모든 클러스터 관리

---

## 🛠️ 트러블슈팅

### 클러스터 생성 실패 시
```bash
# 클러스터 생성 실패 원인 확인
aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.Status.StateChangeReason' --output text

# 로그 확인
aws logs describe-log-groups --log-group-name-prefix "/aws/emr"
```

### 보안 그룹 규칙 추가 실패 시
```bash
# 기존 규칙 확인
aws ec2 describe-security-groups --group-ids $NEW_EMR_MASTER_SG \
  --query 'SecurityGroups[0].IpPermissions'

# 중복 규칙 제거 후 재시도
aws ec2 revoke-security-group-ingress --group-id $NEW_EMR_MASTER_SG \
  --protocol tcp --port 7001 --source-group $PROMETHEUS_SG
```

### Prometheus 타겟이 DOWN 상태일 때
```bash
# 네트워크 연결 확인
telnet $NEW_EMR_MASTER_DNS 9100
telnet $NEW_EMR_MASTER_DNS 7001

# Node Exporter 서비스 상태 확인 (EMR 노드에서)
sudo systemctl status node_exporter
```

---

## 📝 정리 및 정리

### 클러스터 종료 (테스트 완료 후)
```bash
# 새 EMR 클러스터 종료
aws emr terminate-clusters --cluster-ids $NEW_CLUSTER_ID

# 종료 상태 확인
aws emr describe-cluster --cluster-id $NEW_CLUSTER_ID \
  --query 'Cluster.Status.State' --output text
```

### 비용 최적화 팁
- 테스트 완료 후 불필요한 클러스터는 즉시 종료
- 인스턴스 타입을 필요에 맞게 조정 (m5.large 등)
- 스팟 인스턴스 활용 고려

### 보안 고려사항
- 실제 운영 환경에서는 보안 그룹 규칙을 더 제한적으로 설정
- 키페어 관리 및 SSH 접근 제한
- S3 버킷 접근 권한 최소화
