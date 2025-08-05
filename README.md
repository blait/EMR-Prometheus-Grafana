# EMR Monitoring with Prometheus & Grafana

AWS EMR 클러스터를 Prometheus/Grafana로 모니터링하는 완전한 솔루션입니다.

## 📋 프로젝트 개요

- **목적**: EMR 클러스터(Hadoop + Spark)의 실시간 모니터링 시스템 구축
- **구성**: Prometheus + Grafana + Alertmanager + SNS 연동
- **특징**: CloudFormation 기반 자동화 + 추가 EMR 클러스터 연동 가이드

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
├── README.md                           # 프로젝트 개요
├── cloudformation/
│   ├── emrMonitoring.cf.json          # 메인 CloudFormation 템플릿
│   └── emrClusterforPrometheusBlog.json # EMR 클러스터 중첩 스택
├── scripts/
│   ├── bootstrap_monitoring_6_series.sh # EMR Bootstrap 스크립트
│   ├── setup-prometheus.sh            # Prometheus 서버 설치
│   ├── setup-alertmanager.sh          # Alertmanager 설치
│   ├── setup-grafana.sh               # Grafana 설치
│   ├── setup-alertmanager-sns-forwarder-fixed.sh # SNS 연동 (수정버전)
│   └── wordcount_spark.py             # PySpark 테스트 스크립트
├── guides/
│   ├── initial-setup.md               # 초기 설치 가이드
│   ├── add-emr-cluster.md             # 추가 EMR 클러스터 연동 가이드
│   └── troubleshooting.md             # 트러블슈팅 가이드
└── examples/
    ├── prometheus.yml                  # Prometheus 설정 예시
    ├── alertmanager.yml               # Alertmanager 설정 예시
    └── grafana-dashboards/            # Grafana 대시보드 JSON 파일들
```
