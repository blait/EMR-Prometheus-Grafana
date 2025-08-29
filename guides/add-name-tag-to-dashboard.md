# EMR Name 태그를 Grafana 대시보드 변수로 추가하기

## 개요
EMR 인스턴스의 Name 태그 값을 Prometheus 메트릭에 추가하여 Grafana 대시보드에서 클러스터 이름으로 선택할 수 있도록 설정합니다.

<img width="1339" height="360" alt="image" src="https://github.com/user-attachments/assets/da84ffd3-9047-4ce4-917b-75a5f5cb85cb" />


## 현재 상태
- 대시보드 변수: `job`, `cluster_id`, `instance`
- 목표: `cluster_name` 변수 추가 (Name 태그 기반)

## 1단계: 현재 Prometheus 설정 백업

```bash
# Prometheus 서버에 접속
ssh -i ~/.ssh/emr-skt.pem ec2-user@[Prometheus Grafana Server IP]

# 현재 설정 백업
sudo cp /etc/prometheus/conf/prometheus.yml /etc/prometheus/conf/prometheus.yml.backup
```

## 2단계: Prometheus 설정 수정

각 EMR 관련 job의 `relabel_configs`에 Name 태그 매핑을 추가합니다:

```yaml
# 기존 relabel_configs 아래에 추가
- source_labels: [__meta_ec2_tag_Name]
  target_label: cluster_name
```

### 수정할 job 목록:
- `hadoop`
- `hadoop_hdfs_namenode`
- `hadoop_hdfs_datanode`
- `hadoop_yarn_resourcemanager`
- `hadoop_yarn_nodemanager`
- `hive_server2`
- `hive_metastore`

### 예시 (hadoop job):
```yaml
- job_name: 'hadoop'
  scrape_interval: 15s
  ec2_sd_configs:
  - region: 
    profile: EMR_EC2_DefaultRole
    port: 9100
    filters:
    - name: tag:application
      values:
      - hadoop
      
  relabel_configs:
  - source_labels: [__meta_ec2_instance_id]
    target_label: instance
  - source_labels: [__meta_ec2_tag_aws_elasticmapreduce_job_flow_id]
    target_label: cluster_id
  - source_labels: [__meta_ec2_tag_Name]  # 이 라인 추가
    target_label: cluster_name            # 이 라인 추가
```

## 3단계: Static 설정에도 cluster_name 추가

```yaml
# emr-spark-master job 예시
- job_name: 'emr-spark-master'
  static_configs:
    - targets: ['ec2-xxxx.compute-1.amazonaws.com:7001']
      labels:
        cluster_id: 'emr-spark-additional'
        cluster_name: 'EMR-Spark-Monitoring'  # 이 라인 추가
        node_type: 'master'
```

## 4단계: Prometheus 재시작

```bash
# 설정 파일 문법 검증
sudo /opt/prometheus/promtool check config /etc/prometheus/conf/prometheus.yml

# Prometheus 재시작
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

## 5단계: 검증

### 5.0 Prometheus Server 에서 메트릭 확인
1. [Prometheus Grafana Server IP] 서버 ssh 접속 
2. 다음 커맨드 전송 
  ```bash
    curl -s 'http://localhost:9090/api/v1/label/cluster_name/values' 
  ```
3. 다음과 같이 cluster_name 에 대한 데이터가 나오면 성공 
   ```bash
   {"status":"success","data":["EMR cluster for Prometheus Blog","EMR-7.9-Monitoring","EMR-Spark-Monitoring"]}
   ```



### 5.1 Prometheus UI에서 확인
1. `http://[Prometheus Grafana Server IP]:9090` 접속
2. Status > Targets에서 라벨 확인
3. Graph에서 `{cluster_name="EMR-Spark-Monitoring"}` 쿼리 테스트

### 5.2 메트릭 라벨 확인
```promql
# 예시 쿼리
up{cluster_name!=""}
node_cpu_seconds_total{cluster_name="EMR-Spark-Monitoring"}
```

## 6단계: Grafana 대시보드 변수 추가

### 6.1 대시보드 설정 접속
1. Grafana (`http://[Prometheus Grafana Server IP]:3000`) 접속
2. 대시보드 > Settings (상단 톱니바퀴) > Variables

### 6.2 새 변수 생성
- **Name**: `cluster_name`
- **Type**: `Query`
- **Data source**: `Prometheus`
- **Query**: `label_values(cluster_name)`
- **Refresh**: `On Dashboard Load`
- **Multi-value**: `true`
- **Include All**: `true`

### 6.3 대시보드 패널 쿼리 수정 (각 패널 톱니바퀴 아이콘)
기존 쿼리에 `cluster_name` 필터 추가:
```promql
# 기존
node_cpu_seconds_total{job="$job", instance="$instance"}

# 수정 후
node_cpu_seconds_total{job="$job", instance="$instance", cluster_name=~"$cluster_name"}

#example (YARN - Resource Manager)
sum by (job) (
  yarn_resourcemanager_clustermetrics_num_active_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"} +
  yarn_resourcemanager_clustermetrics_num_decommissioning_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"} +
  yarn_resourcemanager_clustermetrics_num_lost_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"} +
  yarn_resourcemanager_clustermetrics_num_rebooted_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"} +
  yarn_resourcemanager_clustermetrics_num_shutdown_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"} +
  yarn_resourcemanager_clustermetrics_num_unhealthy_nms {job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"}
)
```

### 6.4 Grafana 서버 대시보드 파일에서 직접 수정 
1. Grafana 서버 내 /var/lib/grafana/dashboards 위치에 대시보드 파일 있음 
2. 예시) /var/lib/grafana/dashboards/YARN+-+Resource+Manager.json 파일 
   1. cluster_name 변수 추가 
      1. templating 구간을 찾음 
      2. 변수 중 가장아래 다음내용 추가 
      3.       
         ```bash
         {
           "allValue": null,
           "current": {
             "text": "All",
             "value": [""]
           },
           "datasource": "Prometheus",
           "definition": "label_values(cluster_name)",
           "hide": 0,
           "includeAll": true,
           "label": null,
           "multi": true,
           "name": "cluster_name",
           "options": [],
           "query": "label_values(cluster_name)",
           "refresh": 1,
           "regex": "",
           "skipUrlSync": false,
           "sort": 0,
           "tagValuesQuery": "",
           "tags": [],
           "tagsQuery": "",
           "type": "query",
           "useTags": false
         }
         ```
      4. Grafana 재시작 sudo systemctl restart grafana-server
   2. 모든 Prometheus 쿼리에 cluster_name 필터를 자동으로 추가하여 선택한 클러스터의 데이터만 표시되도록 함
      1. 리눅스에서 이스케이프 잡기가 쉽지 않아서 mac 에서 다음과 같이 했더니 성공 
         1. sed -i '' 's/instance=~'\''$instance'\''}/instance=~'\''$instance'\'', cluster_name=~'\''$cluster_name'\''}/g' /tmp/yarn-dashboard-correct.json
      2. 수정 전 
         1. yarn_resourcemanager_clustermetrics_num_active_nms{job="$job", cluster_id=~'$cluster', instance=~'$instance'}
      3. 수정 후 
         1. yarn_resourcemanager_clustermetrics_num_active_nms{job="$job", cluster_id=~'$cluster', instance=~'$instance', cluster_name=~"$cluster_name"}
   3. grafana 재시작 
      1. sudo systemctl restart grafana-server




## 7단계: 최종 검증

### 7.1 대시보드 상단 확인
- 드롭다운에 `cluster_name` 변수가 표시되는지 확인
- EMR Name 태그 값들이 선택 옵션으로 나타나는지 확인

### 7.2 필터링 테스트
- 특정 클러스터 이름(cluster_name) 선택 시 해당 클러스터 메트릭만 표시되는지 확인

## 문제 해결

### Prometheus 재시작 실패
```bash
# 로그 확인
sudo journalctl -u prometheus -f

# 설정 파일 문법 오류 확인
sudo /opt/prometheus/promtool check config /etc/prometheus/conf/prometheus.yml
```

### 라벨이 나타나지 않는 경우
1. EMR 인스턴스에 Name 태그가 있는지 확인
2. Prometheus Targets에서 라벨이 올바르게 수집되는지 확인
3. 메트릭 스크래핑이 정상적으로 되고 있는지 확인

### Grafana 변수가 비어있는 경우
1. Prometheus 데이터소스 연결 확인
2. `label_values(cluster_name)` 쿼리 결과 확인
3. 변수 새로고침 설정 확인


