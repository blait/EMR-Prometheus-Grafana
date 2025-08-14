# EMR 7.9 Spark 애플리케이션 모니터링 가이드

## 📋 개요

기존 EMR 6.0 모니터링 시스템을 EMR 7.9로 업그레이드하고, Spark 애플리케이션별 상세 모니터링을 추가하는 가이드입니다.

## 🎯 주요 개선사항

- ✅ **EMR 7.9 완전 호환**: 기존 모니터링 시스템 그대로 사용
- ✅ **PrometheusServlet 지원**: Spark 애플리케이션별 상세 메트릭  
- ✅ **YARN 프록시 활용**: File SD 기반 자동 Service Discovery

## 🚀 1단계: EMR 7.9 클러스터 생성

### **1.1 EMR Configuration 파일 생성**

```bash
# EMR 설정 파일 생성
cat > emr-7.9-config.json << 'EOF'
[
  {
    "Classification": "hadoop-env",
    "Configurations": [
      {
        "Classification": "export",
        "Properties": {
          "HADOOP_DATANODE_OPTS": "-javaagent:/etc/prometheus/jmx_prometheus_javaagent-0.13.0.jar=7001:/etc/hadoop/conf/hdfs_jmx_config_datanode.yaml -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.port=50103",
          "HADOOP_NAMENODE_OPTS": "-javaagent:/etc/prometheus/jmx_prometheus_javaagent-0.13.0.jar=7001:/etc/hadoop/conf/hdfs_jmx_config_namenode.yaml -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.port=50103"
        }
      }
    ]
  }
]
EOF
```

### **1.2 EMR 7.9 클러스터 생성**

```bash
# EMR 7.9 클러스터 생성 (기존 설정 활용)
aws emr create-cluster \
  --name "EMR-7.9-Monitoring" \
  --release-label emr-7.9.0 \
  --applications Name=Hadoop Name=Spark \
  --ec2-attributes KeyName=your-key-pair,SubnetId=subnet-xxxxxxxxx,InstanceProfile=EMR_EC2_DefaultRole,AdditionalMasterSecurityGroups=sg-xxxxxxxxx,AdditionalSlaveSecurityGroups=sg-xxxxxxxxx \
  --instance-groups InstanceGroupType=MASTER,InstanceType=m5.xlarge,InstanceCount=1 InstanceGroupType=CORE,InstanceType=m5.xlarge,InstanceCount=2 \
  --service-role EMR_DefaultRole \
  --log-uri s3://your-bucket/emr-logs/ \
  --visible-to-all-users \
  --bootstrap-actions Path=s3://your-bucket/emr-monitoring/scripts/bootstrap_monitoring_6_series.sh \
  --configurations file://emr-7.9-config.json \
  --region us-east-1
```

### **1.4 보안그룹 설정 (중요)**

```bash
# EMR 클러스터와 Prometheus 서버의 보안그룹 ID 확인
EMR_CLUSTER_ID="your-cluster-id"
PROMETHEUS_DNS="your-prometheus-server-dns"

# EMR 클러스터 보안그룹 확인
aws emr describe-cluster --cluster-id $EMR_CLUSTER_ID --region us-east-1 --query 'Cluster.Ec2InstanceAttributes.AdditionalMasterSecurityGroups[0]' --output text

# Prometheus 서버 보안그룹 확인
PROMETHEUS_INSTANCE_ID=$(aws ec2 describe-instances --region us-east-1 --filters "Name=dns-name,Values=$PROMETHEUS_DNS" --query 'Reservations[0].Instances[0].InstanceId' --output text)
PROMETHEUS_SG=$(aws ec2 describe-instances --instance-ids $PROMETHEUS_INSTANCE_ID --region us-east-1 --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# EMR 마스터 노드 보안그룹에 YARN 프록시 포트(20888) 접근 허용 추가
aws ec2 authorize-security-group-ingress \
  --group-id EMR_SECURITY_GROUP_ID \
  --protocol tcp \
  --port 20888 \
  --source-group $PROMETHEUS_SG \
  --region us-east-1

echo "보안그룹 설정 완료: Prometheus 서버에서 EMR YARN 프록시(포트 20888) 접근 허용"
```

```bash
# 클러스터 ID 확인
CLUSTER_ID=$(aws emr list-clusters --active --query 'Clusters[0].Id' --output text --region us-east-1)

# Prometheus 자동 발견을 위한 태그 추가 (AWS 콘솔에서 수동 추가 권장)
# Key: application, Value: hadoop
# Key: Name, Value: EMR-7.9-Monitoring
```

## 🔧 2단계: Spark PrometheusServlet 활용

### **2.1 PrometheusServlet 설정으로 Spark 애플리케이션 실행**

```bash
```bash
# EMR 마스터 노드에 SSH 접속
ssh -i your-key.pem hadoop@master-node-dns

# 오래 실행되는 PySpark 애플리케이션 생성
cat > /tmp/long_running_spark.py << 'EOF'
from pyspark.sql import SparkSession
import time
import random

spark = SparkSession.builder.appName('LongRunningSparkApp').getOrCreate()

# 큰 데이터셋 생성
data = [(i, random.randint(1, 1000), f'data_{i}') for i in range(1000000)]
df = spark.createDataFrame(data, ['id', 'value', 'text'])

# 여러 번의 무거운 연산 수행 (약 16분 실행)
for iteration in range(100):
    result = df.groupBy('value').count().collect()
    df.cache()
    df.count()
    time.sleep(10)  # 10초 대기
    
    if iteration % 10 == 0:
        print(f'Completed {iteration} iterations')

spark.stop()
EOF

# ⚠️ 중요: 반드시 YARN 모드로 실행 (Local 모드에서는 프록시 접근 불가)
spark-submit \
  --conf spark.metrics.conf.*.sink.prometheusServlet.class=org.apache.spark.metrics.sink.PrometheusServlet \
  --conf spark.metrics.conf.*.sink.prometheusServlet.path=/metrics \
  --master yarn \
  --deploy-mode client \
  --num-executors 2 \
  --executor-cores 1 \
  --executor-memory 2g \
  --driver-memory 2g \
  /tmp/long_running_spark.py

# ⚠️ 필수: Spark 애플리케이션 시작 후 즉시 타겟 업데이트
# Prometheus 서버에서 실행 (별도 터미널 또는 SSH)
ssh prometheus-server
/etc/prometheus/update_spark_targets.sh
```
```

### **2.2 PrometheusServlet 메트릭 확인**

```bash
# YARN에서 실행 중인 Spark 애플리케이션 확인
yarn application -list -appStates RUNNING

# YARN 프록시를 통한 메트릭 확인 (⚠️ Internal hostname 사용 필수)
APP_ID=$(yarn application -list -appStates RUNNING | grep SPARK | awk '{print $1}')
curl "http://$(hostname -f):20888/proxy/$APP_ID/metrics/prometheus" | head -5
```

## 🎯 3단계: File-based Service Discovery 설정

### **3.1 YARN REST API 확인**

```bash
# 실행 중인 Spark 애플리케이션 조회 (⚠️ Internal hostname 사용)
curl -s "http://$(hostname -f):8088/ws/v1/cluster/apps?states=RUNNING&applicationTypes=SPARK" | jq '.apps.app[] | {id: .id, name: .name}'
```

### **3.2 Spark 타겟 업데이트 스크립트 생성**

```bash
# Prometheus 서버에서 실행
# 필요한 디렉토리 생성
sudo mkdir -p /etc/prometheus/targets

cat > /etc/prometheus/update_spark_targets.sh << 'EOF'
#!/bin/bash
TARGETS_FILE="/etc/prometheus/targets/spark.json"
EMR_MASTER="your-emr-master-dns"  # EMR 마스터 노드 DNS로 변경
YARN_API="http://$EMR_MASTER:8088/ws/v1/cluster/apps?states=RUNNING&applicationTypes=SPARK"

# YARN API 호출 및 JSON 생성 (⚠️ 원격 EMR 마스터 노드 접근)
curl -s "$YARN_API" | jq --arg HOSTNAME "$EMR_MASTER" '[
  .apps.app[]? | {
    targets: [$HOSTNAME + ":20888"],
    labels: {
      metrics_path: ("/proxy/" + .id + "/metrics/prometheus"),
      application_id: .id,
      application_name: .name,
      job: "spark-apps"
    }
  }
]' | sudo tee "$TARGETS_FILE" > /dev/null

# 파일이 비어있으면 빈 배열로 설정
if [ ! -s "$TARGETS_FILE" ]; then
    echo "[]" | sudo tee "$TARGETS_FILE" > /dev/null
fi
EOF

chmod +x /etc/prometheus/update_spark_targets.sh
```

### **3.3 주기적 업데이트 설정**

```bash
# Prometheus 서버에서 Cron 설정 (30초마다 실행)
(crontab -l 2>/dev/null; echo "* * * * * /etc/prometheus/update_spark_targets.sh") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * sleep 30; /etc/prometheus/update_spark_targets.sh") | crontab -

# 초기 실행
/etc/prometheus/update_spark_targets.sh
```

### **3.4 생성된 타겟 파일 확인**

```bash
# 생성된 spark.json 파일 확인
cat /etc/prometheus/targets/spark.json

# 예시 출력:
# [
#   {
#     "targets": ["ip-172-31-29-129.ec2.internal:20888"],
#     "labels": {
#       "metrics_path": "/proxy/application_1755006788901_0003/metrics/prometheus",
#       "application_id": "application_1755006788901_0003",
#       "application_name": "Spark Pi",
#       "job": "spark-apps"
#     }
#   }
# ]
```

## ⚙️ 4단계: Prometheus 설정 업데이트

### **4.1 기존 Prometheus 설정 백업**

```bash
# Prometheus 서버에 SSH 접속
ssh -i your-key.pem ec2-user@prometheus-server

# 기존 설정 백업
sudo cp /etc/prometheus/conf/prometheus.yml /etc/prometheus/conf/prometheus.yml.backup
```

### **4.2 기존 Prometheus 설정 확인**

```bash
# jq 설치 (JSON 파싱용)
sudo yum install -y jq

# 기존 EMR 클러스터가 정상적으로 모니터링되는지 확인
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "hadoop") | {instance: .labels.instance, health: .health}'

# EMR 7.9 클러스터도 자동으로 발견되는지 확인 (application=hadoop 태그 필요)
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("hadoop")) | {job: .labels.job, instance: .labels.instance, health: .health}'
```

### **4.3 Spark 애플리케이션 모니터링 추가**

```bash
# Spark 애플리케이션 File SD 설정 추가
sudo tee -a /opt/prometheus/prometheus.yml > /dev/null << 'EOF'

  # Spark Applications via YARN Proxy (File SD)
  - job_name: 'spark-apps'
    file_sd_configs:
      - files: ['/etc/prometheus/targets/spark.json']
        refresh_interval: 30s
    relabel_configs:
      - source_labels: [metrics_path]
        target_label: __metrics_path__
    scrape_interval: 15s
EOF
```

### **4.4 Prometheus 설정 검증 및 리로드**

```bash
# 설정 검증
tail -10 /etc/prometheus/conf/prometheus.yml

# Prometheus 리로드
sudo systemctl restart prometheus

# 상태 확인
sudo systemctl status prometheus --no-pager -l
```

## 📊 5단계: 모니터링 확인

### **5.1 Prometheus 타겟 확인**

```bash
# Prometheus 웹 UI에서 확인
# http://prometheus-server:9090/targets

# 또는 API로 확인
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "spark-apps") | {job: .labels.job, instance: .labels.instance, health: .health}'
```

### **5.2 Spark 메트릭 쿼리 테스트**

```bash
# ⚠️ 주의: 새 Spark 애플리케이션 시작 후 반드시 타겟 업데이트 실행
# Prometheus 서버에서:
/etc/prometheus/update_spark_targets.sh

# 1. 먼저 실행 중인 애플리케이션 ID 확인
APP_ID=$(curl -s 'http://your-emr-master-dns:8088/ws/v1/cluster/apps?states=RUNNING&applicationTypes=SPARK' | jq -r '.apps.app[0].id')
echo "Application ID: $APP_ID"

# ⚠️ 중요: APP_ID 변수가 제대로 설정되었는지 확인
if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo "ERROR: 실행 중인 Spark 애플리케이션이 없습니다."
    exit 1
fi

# 2. 직접 메트릭 엔드포인트 접근 확인
echo "메트릭 엔드포인트 테스트:"
curl -s "http://your-emr-master-dns:20888/proxy/${APP_ID}/metrics/prometheus" | grep 'maxMem_MB_Number' | head -1

# 3. Prometheus에서 사용 가능한 메트릭 확인
echo "Prometheus 메트릭 목록 확인:"
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | jq -r ".data[] | select(contains(\"${APP_ID}\") and contains(\"maxMem_MB_Number\"))"

# 4. 구체적인 애플리케이션 ID로 메트릭 쿼리 (⚠️ 변수 처리 주의)
echo "Prometheus 메트릭 쿼리:"
METRIC_NAME="metrics_application_${APP_ID}_driver_BlockManager_memory_maxMem_MB_Number"
curl -s "http://localhost:9090/api/v1/query?query=${METRIC_NAME}" | jq '.data.result[0] | {metric: .metric.application_id, value: .value[1]}'

# 5. 실시간 메트릭 수집 검증
echo "첫 번째 측정:"
curl -s "http://localhost:9090/api/v1/query?query=${METRIC_NAME}" | jq '.data.result[0] | {value: .value[1], timestamp: .value[0]}'

echo "30초 후 두 번째 측정:"
sleep 30
curl -s "http://localhost:9090/api/v1/query?query=${METRIC_NAME}" | jq '.data.result[0] | {value: .value[1], timestamp: .value[0]}'

# 6. 변화하는 메트릭으로 실시간 확인 (JVM CPU 시간)
CPU_METRIC="metrics_application_${APP_ID}_driver_JVMCPU_jvmCpuTime_Value"
echo "JVM CPU 시간 메트릭:"
curl -s "http://localhost:9090/api/v1/query?query=${CPU_METRIC}" | jq '.data.result[0] | {value: .value[1], timestamp: .value[0]}' 2>/dev/null || echo 'JVM CPU 메트릭 수집 중...'
```

### **5.3 수집 가능한 주요 Spark 메트릭**

```
# 메모리 사용량 (⚠️ 실제 메트릭 이름에는 애플리케이션 ID 포함)
metrics_application_*_driver_BlockManager_memory_maxMem_MB_Number     # 예: 9267 (9.2GB)
metrics_application_*_driver_BlockManager_memory_memUsed_MB_Value

# CPU 사용량  
metrics_application_*_driver_JVMCPU_jvmCpuTime_Value

# 활성 태스크
metrics_application_*_driver_executor_threadpool_activeTasks_Value

# GC 정보
metrics_application_*_driver_jvm_gc_*

# 디스크 사용량
metrics_application_*_driver_BlockManager_disk_diskSpaceUsed_MB_Value

# 패턴 매칭으로 메트릭 검색 예시
{__name__=~".*maxMem_MB_Number"}                    # 메모리 관련
{__name__=~".*application_.*jvm_gc.*"}              # GC 관련
{__name__=~".*BlockManager.*"}                      # BlockManager 관련
```

### **트러블슈팅**

**문제**: SparkPi 애플리케이션이 금방 종료됨
**해결**: 위의 PySpark 예제 사용 또는 실제 Streaming/배치 작업 실행

**문제**: 메트릭 쿼리 결과가 null
**해결**: 
1. 애플리케이션이 실행 중인지 확인: `yarn application -list -appStates RUNNING`
2. 직접 메트릭 엔드포인트 접근: `curl http://emr-master:20888/proxy/APP_ID/metrics/prometheus`
3. Prometheus 타겟 상태 확인: `health: "up"` 여부




## 🔍 7단계: 트러블슈팅

### **7.1 일반적인 문제 해결**

```bash
# 1. YARN 프록시 서버 상태 확인
netstat -tlnp | grep 20888
ps aux | grep proxyserver

# 2. 타겟 파일 업데이트 확인
cat /etc/prometheus/targets/spark.json
ls -la /etc/prometheus/targets/

# 3. Cron 작업 확인
crontab -l
tail -f /var/log/cron

# 4. Spark 애플리케이션 상태 확인
yarn application -list -appStates RUNNING

# 5. Prometheus 타겟 상태 확인
curl http://localhost:9090/api/v1/targets
```

### **7.2 메트릭이 수집되지 않는 경우**

```bash
# 1. PrometheusServlet 설정 확인
APP_ID=$(yarn application -list -appStates RUNNING | grep SPARK | awk '{print $1}')
curl "http://localhost:20888/proxy/$APP_ID/metrics/prometheus"

# 2. 타겟 파일 수동 업데이트
/opt/prometheus/update_spark_targets.sh
cat /etc/prometheus/targets/spark.json

# 3. Prometheus 설정 검증
sudo /opt/prometheus/promtool check config /opt/prometheus/prometheus.yml

# 4. File SD 권한 확인
ls -la /etc/prometheus/targets/
sudo chown prometheus:prometheus /etc/prometheus/targets/spark.json
```

### **7.3 디버깅 명령어**

```bash
# YARN API 직접 호출
curl -s "http://$(hostname -f):8088/ws/v1/cluster/apps?states=RUNNING&applicationTypes=SPARK"

# 수동으로 타겟 생성 테스트
echo '[{"targets":["localhost:20888"],"labels":{"metrics_path":"/proxy/application_test/metrics/prometheus"}}]' | sudo tee /etc/prometheus/targets/spark.json

# Prometheus 로그 확인
sudo journalctl -u prometheus -f
```

## 📋 요약

이 가이드를 통해 다음을 달성할 수 있습니다:

1. ✅ **EMR 7.9 완전 호환**: 기존 모니터링 시스템 그대로 활용
2. ✅ **Spark 애플리케이션 모니터링**: PrometheusServlet을 통한 상세 메트릭 수집
3. ✅ **자동 Service Discovery**: File SD 기반 동적 타겟 관리 (HTTP 서버 불필요)
4. ✅ **확장 가능한 구조**: 새로운 애플리케이션 자동 발견 및 모니터링
5. ✅ **운영 편의성**: 간단한 스크립트와 Cron 기반 자동화

**EMR 7.9에서 기존 시스템의 안정성을 유지하면서 Spark 애플리케이션 모니터링을 크게 향상시킬 수 있습니다.**
