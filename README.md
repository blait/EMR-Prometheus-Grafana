# EMR Monitoring with Prometheus & Grafana

AWS EMR 클러스터를 Prometheus/Grafana로 모니터링하는 완전한 솔루션입니다.

## 📋 프로젝트 개요

- **목적**: EMR 클러스터(Hadoop + Spark)의 실시간 모니터링 시스템 구축
- **구성**: Prometheus + Grafana + Alertmanager + SNS 연동
- **특징**: CloudFormation 기반 자동화 + 추가 EMR 클러스터 연동 가이드

## 🚀 빠른 시작 (CloudFormation 배포)

### 1. 사전 준비사항

- AWS CLI 설치 및 구성
- 적절한 IAM 권한 (EC2, EMR, SNS, CloudFormation 등)
- Key Pair 생성 (EC2 인스턴스 접근용)
- VPC 및 서브넷 ID 확인

### 2. 원클릭 배포

메인 CloudFormation 템플릿 하나로 전체 인프라를 배포할 수 있습니다:

```bash
aws cloudformation create-stack \
  --stack-name emr-monitoring-complete \
  --template-body file://cloudformation/emrMonitoring.cf.json \
  --parameters \
    ParameterKey=VPC,ParameterValue=vpc-xxxxxxxxx \
    ParameterKey=Subnet,ParameterValue=subnet-xxxxxxxxx \
    ParameterKey=KeyName,ParameterValue=your-key-pair \
    ParameterKey=EMRKeyName,ParameterValue=your-key-pair \
    ParameterKey=EMRClusterName,ParameterValue=emr-monitoring-cluster \
    ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
  --capabilities CAPABILITY_IAM
```

### 3. 주요 매개변수

| 매개변수 | 설명 | 기본값 | 예시 |
|---------|------|--------|------|
| `VPC` | VPC ID (필수) | - | `vpc-12345678` |
| `Subnet` | 서브넷 ID (필수) | - | `subnet-12345678` |
| `KeyName` | Prometheus 서버용 Key Pair | - | `my-keypair` |
| `EMRKeyName` | EMR 클러스터용 Key Pair | - | `my-keypair` |
| `EMRClusterName` | EMR 클러스터 이름 | `EMRClusterForPrometheus` | `my-emr-cluster` |
| `EmailAddress` | 알림 받을 이메일 | - | `admin@company.com` |
| `InstanceType` | Prometheus 서버 인스턴스 타입 | `t3.medium` | `t3.large` |
| `MasterInstanceType` | EMR 마스터 인스턴스 타입 | `m5.xlarge` | `m5.2xlarge` |
| `CoreInstanceType` | EMR 코어 인스턴스 타입 | `m5.xlarge` | `m5.2xlarge` |
| `CoreInstanceCount` | EMR 코어 인스턴스 개수 | `2` | `3` |


### 4. 배포 상태 확인

```bash
# 스택 배포 상태 확인
aws cloudformation describe-stacks \
  --stack-name emr-monitoring-complete \
  --query 'Stacks[0].StackStatus'

# 스택 출력값 확인 (서비스 URL 등)
aws cloudformation describe-stacks \
  --stack-name emr-monitoring-complete \
  --query 'Stacks[0].Outputs'
```

### 5. 서비스 접근

배포 완료 후 CloudFormation 출력값에서 확인할 수 있는 URL로 접근:

- **Grafana**: `http://<PrometheusServerPublicIP>:3000`
  - 기본 로그인: admin/admin
- **Prometheus**: `http://<PrometheusServerPublicIP>:9090`
- **Alertmanager**: `http://<PrometheusServerPublicIP>:9093`

### 7. 스택 삭제

```bash
aws cloudformation delete-stack --stack-name emr-monitoring-complete
```

> **참고**: 중첩 스택으로 생성된 모든 리소스가 자동으로 삭제됩니다.

### 8. 추가 EMR 클러스터 연동

기존 모니터링 시스템에 새로운 EMR 클러스터를 추가하려면 다음 가이드를 참조하세요:

📖 **[추가 EMR 클러스터 연동 가이드](guides/add-emr-cluster.md)**

이 가이드에서는 다음 내용을 다룹니다:
- 기존 모니터링 시스템 정보 확인
- 새 EMR 클러스터 생성 및 모니터링 설정
- Prometheus 설정 업데이트
- Grafana 대시보드 연동
- 알림 규칙 확장

## 🏗️ 아키텍처

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EMR Cluster   │    │   Prometheus    │    │    Grafana      │
│  (Hadoop+Spark) │───▶│     Server      │───▶│   Dashboard     │
│                 │    │                 │    │                 │
│ • Node Exporter │    │ • Metrics Store │    │ • Visualization │
│ • JMX Exporter  │    │ • Alert Rules   │    │ • Dashboards    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │  Alertmanager   │───▶│   SNS Topic     │
                       │                 │    │                 │
                       │ • Alert Routing │    │ • Email Alerts  │
                       │ • SNS Forwarder │    │ • Notifications │
                       └─────────────────┘    └─────────────────┘
```

## 📁 프로젝트 구조

```
emr-mo-skt/
├── README.md                                    # 프로젝트 개요 및 사용법
├── emr-monitoring-bootstrap.sh                 # EMR 클러스터 모니터링 부트스트랩 스크립트
├── sourcecode.zip                              # 소스코드 압축 파일
├── cloudformation/                             # CloudFormation 템플릿 모음
│   ├── emrMonitoring.cf.json                   # 메인 모니터링 인프라 템플릿
│   ├── emrClusterforPrometheusBlog.json        # EMR 클러스터 생성 템플릿
│   ├── IamForPrometheus.json                   # Prometheus용 IAM 역할 템플릿
│   └── SNSForPrometheus.json                   # SNS 알림 설정 템플릿
├── config/                                     # 설정 파일 모음
│   ├── alertmanager/
│   │   └── alertmanager.yml                    # Alertmanager 메인 설정
│   ├── alertmanager-sns-forwarder/
│   │   ├── alertmanager-sns-forwarder          # SNS 포워더 바이너리
│   │   └── default.tmpl                        # 알림 메시지 템플릿
│   ├── emr-scripts/
│   │   └── yarn_jmx_env_setup.txt             # YARN JMX 환경 설정
│   ├── grafana/
│   │   ├── grafana_dashboard.yaml              # Grafana 대시보드 프로비저닝
│   │   └── grafana_prometheus_datasource.yaml  # Prometheus 데이터소스 설정
│   ├── grafana-dashboards/                     # Grafana 대시보드 JSON 파일들
│   │   ├── HDFS+-+DataNode.json               # HDFS DataNode 대시보드
│   │   ├── HDFS+-+NameNode.json               # HDFS NameNode 대시보드
│   │   ├── JVM+Metrics.json                   # JVM 메트릭 대시보드
│   │   ├── Log+Metrics.json                   # 로그 메트릭 대시보드
│   │   ├── OS+Level+Metrics.json              # OS 레벨 메트릭 대시보드
│   │   ├── RPC+Metrics.json                   # RPC 메트릭 대시보드
│   │   ├── Spark-Application-Resources-Real.json # Spark 애플리케이션 리소스 대시보드
│   │   ├── YARN+-+Node+Manager.json           # YARN NodeManager 대시보드
│   │   ├── YARN+-+Queues.json                 # YARN 큐 대시보드
│   │   └── YARN+-+Resource+Manager.json       # YARN ResourceManager 대시보드
│   ├── jmx-exporter/                          # JMX Exporter 설정 파일들
│   │   ├── hdfs_jmx_config_datanode.yaml      # HDFS DataNode JMX 설정
│   │   ├── hdfs_jmx_config_namenode.yaml      # HDFS NameNode JMX 설정
│   │   ├── yarn_jmx_config_node_manager.yaml  # YARN NodeManager JMX 설정
│   │   └── yarn_jmx_config_resource_manager.yaml # YARN ResourceManager JMX 설정
│   ├── prometheus/
│   │   ├── prometheus.yml                      # Prometheus 메인 설정
│   │   └── rules.yml                          # Prometheus 알림 규칙
│   └── service-files/                         # systemd 서비스 파일들
│       ├── alertmanager-sns-forwarder.service # SNS 포워더 서비스
│       ├── alertmanager.service               # Alertmanager 서비스
│       ├── node_exporter.service              # Node Exporter 서비스
│       ├── prometheus.service                 # Prometheus 서비스
│       └── spark-app-exporter.service         # Spark 애플리케이션 Exporter 서비스
├── scripts/                                   # 설치 및 설정 스크립트들
│   ├── after_provision_action.sh              # 프로비저닝 후 실행 스크립트
│   ├── bootstrap_monitoring_6_series.sh       # EMR 6.x 시리즈용 부트스트랩 스크립트
│   ├── install_spark_exporter.sh              # Spark Exporter 설치 스크립트
│   ├── setup-alertmanager-sns-forwarder-fixed.sh # SNS 포워더 설치 (수정 버전)
│   ├── setup-alertmanager-sns-forwarder-original.sh # SNS 포워더 설치 (원본 버전)
│   ├── setup-alertmanager.sh                  # Alertmanager 설치 스크립트
│   ├── setup-grafana.sh                       # Grafana 설치 스크립트
│   ├── setup-prometheus.sh                    # Prometheus 설치 스크립트
│   ├── spark_app_exporter.py                  # Spark 애플리케이션 메트릭 수집기
│   ├── update_prometheus_config.sh            # Prometheus 설정 업데이트 스크립트
│   └── wordcount_spark.py                     # Spark WordCount 테스트 애플리케이션
├── guides/                                    # 사용자 가이드 문서들
│   └── add-emr-cluster.md                     # 추가 EMR 클러스터 연동 가이드
├── examples/                                  # 예제 및 참고 파일들
│   └── grafana-dashboards/                    # Grafana 대시보드 예제 (빈 폴더)
└── sourcecode/                                # Java 소스코드 (WordCount 예제)
    └── Wordcount/                             # Maven 프로젝트
        ├── .classpath                         # Eclipse 클래스패스 설정
        ├── .project                           # Eclipse 프로젝트 설정
        ├── pom.xml                            # Maven 프로젝트 설정
        ├── .settings/                         # Eclipse 설정 폴더
        └── src/main/java/com/amazonaws/support/training/emr/
            └── Wordcount.java                 # WordCount Java 구현체
```
