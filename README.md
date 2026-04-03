# Fraud Detection Analytics Platform

A production-grade, real-time fraud detection system built as a portfolio project across 5 phases. Each phase is independently deployable and builds on the previous, demonstrating the full lifecycle of a modern data engineering and ML platform.

---

## Overview

This platform simulates a financial institution's fraud detection infrastructure — ingesting payment transactions at scale, transforming them through a lakehouse architecture, training and serving a machine learning model in real time, and exposing operational dashboards for monitoring.

**The system handles the full data lifecycle:**
- Streaming ingestion at configurable TPS (transactions per second)
- ACID-compliant lakehouse storage with Delta Lake
- Batch transformation through a medallion architecture (Bronze → Silver → Gold)
- ML model training, versioning, and real-time scoring
- Operational observability with metrics, alerts, and dashboards

---

## Tech Stack

| Layer | Technology | Role |
|---|---|---|
| **Ingestion** | Apache Kafka 7.7 | Distributed event streaming |
| **Schema** | Confluent Schema Registry | Avro schema enforcement + evolution |
| **Storage** | MinIO | S3-compatible object store (Delta Lake backend) |
| **Table Format** | Delta Lake | ACID transactions on Parquet files |
| **Stream Processing** | Apache Spark 3.5 Structured Streaming | Kafka → Delta Lake writer |
| **SQL Engine** | Trino 435 | Federated SQL over Delta Lake |
| **Transformation** | dbt (dbt-trino) | SQL-based Bronze → Silver → Gold transforms |
| **Orchestration** | Apache Airflow 2.8 | Pipeline scheduling and dependency management |
| **ML Tracking** | MLflow 2.10 | Experiment tracking + model registry |
| **Feature Store** | Redis 7 | Sub-millisecond real-time feature lookup |
| **Serving** | FastAPI + uvicorn | Real-time fraud scoring REST API |
| **Metrics** | Prometheus | Metrics collection and alerting |
| **Dashboards** | Grafana | Operational and ML monitoring dashboards |
| **BI** | Apache Superset | Self-serve business analytics |
| **Infrastructure** | Docker Compose | Full-stack local orchestration |

---

## Architecture — High-Level Process Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW                                      │
│                                                                         │
│  [Python Producer]                                                      │
│       │  Avro-serialised transactions @ configurable TPS               │
│       ▼                                                                 │
│  [Kafka: transactions.raw]  ──bad messages──►  [transactions.dlq]      │
│       │                                                                 │
│       │  Spark Structured Streaming (micro-batch every 10s)            │
│       ▼                                                                 │
│  [Quality Checks] ──failed──► [transactions.dlq]                       │
│       │ passed                                                          │
│       ▼                                                                 │
│  [Delta Lake Bronze] ── Parquet partitioned by event_date ──► [MinIO]  │
│       │                                                                 │
│       │  Airflow DAG (every 15 min) → dbt                              │
│       ▼                                                                 │
│  [Silver: stg_transactions + int_transactions_enriched]                 │
│       │  type casts, merchant join, risk flags, rolling windows        │
│       ▼                                                                 │
│  [Gold: mart_fraud_features, mart_hourly_metrics, mart_user_risk]       │
│       │                                                                 │
│       ├──────────────────────────────────────┐                         │
│       │  feature_writer.py (Airflow step)    │  train.py (weekly)      │
│       ▼                                      ▼                         │
│  [Redis Feature Store]              [MLflow Model Registry]            │
│       │  user_features:{id}              Production model               │
│       │                                      │                         │
│       └──────────────┬───────────────────────┘                         │
│                      ▼                                                  │
│              [FastAPI /predict]                                         │
│                      │  fraud_probability, risk_tier, latency_ms       │
│                      ▼                                                  │
│              [Predictions Log]  ──► Postgres                           │
│                      │                                                  │
│                      ▼                                                  │
│  [Prometheus] ◄── /metrics ── [fraud-api, kafka-exporter]              │
│       │                                                                 │
│       ▼                                                                 │
│  [Grafana]  Pipeline Health + ML Monitoring dashboards                 │
│  [Superset] Business analytics over Gold tables via Trino              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Service Map

| Service | URL | Credentials |
|---|---|---|
| Kafka UI | http://localhost:8080 | — |
| Schema Registry | http://localhost:8081 | — |
| Airflow | http://localhost:8082 | admin / admin123 |
| Trino | http://localhost:8085 | any username, no password |
| Spark Master UI | http://localhost:8090 | — |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin123 |
| MLflow | http://localhost:5000 | — |
| Fraud API | http://localhost:8000 | — |
| Fraud API Docs | http://localhost:8000/docs | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| Superset | http://localhost:8088 | admin / admin123 |

---

## Repository Structure

```
fraud-platform/
├── docker-compose.yml              # Full stack, grows each phase
├── Makefile                        # make up / down / test / phase{N}-up
├── .env.example                    # All config — copy to .env
│
├── phase1-ingestion/               # Kafka + Avro producer
│   ├── producer/
│   │   ├── producer.py             # Transaction generator
│   │   ├── schemas/transaction.avsc
│   │   └── Dockerfile
│   └── tests/
│
├── phase2-streaming/               # Spark Structured Streaming
│   ├── spark_jobs/
│   │   ├── bronze_writer.py        # Kafka → Delta Bronze
│   │   └── quality_checks.py      # Validation rules
│   └── tests/
│
├── phase3-transforms/              # dbt + Airflow + Trino
│   ├── dbt_project/
│   │   ├── models/
│   │   │   ├── staging/            # Bronze → typed views (Silver)
│   │   │   ├── intermediate/       # Enrichment + aggregation (Silver)
│   │   │   └── marts/              # ML features + metrics (Gold)
│   │   ├── seeds/merchants.csv     # Reference data
│   │   ├── tests/                  # Custom SQL quality tests
│   │   └── macros/                 # generate_schema_name, rolling_window
│   └── airflow/
│       └── dags/fraud_pipeline.py  # Orchestration DAG
│
├── phase4-ml/                      # ML lifecycle
│   ├── features.py                 # Shared feature definitions (training + serving)
│   ├── training/
│   │   ├── train.py                # RandomForest → MLflow
│   │   └── evaluate.py
│   ├── serving/
│   │   ├── main.py                 # FastAPI app
│   │   ├── predictor.py            # MLflow model loader + scorer
│   │   ├── feature_client.py       # Redis lookup + fallback
│   │   └── feature_writer.py       # Gold → Redis (Airflow-triggered)
│   └── tests/
│
├── phase5-analytics/               # Observability + BI
│   ├── grafana/
│   │   ├── provisioning/           # Auto-loaded datasources + dashboards
│   │   └── dashboards/             # Pipeline health + ML monitoring JSON
│   └── superset/
│       └── superset_config.py
│
└── infra/
    ├── minio/init_buckets.sh
    └── trino/
        ├── catalog/delta.properties
        ├── config.properties
        └── jvm.config
```

---

## Getting Started

### Prerequisites
- Docker Desktop or Docker Engine with Compose v2
- 16 GB RAM recommended (all phases running simultaneously)
- 20 GB free disk space

### Setup

```bash
git clone <repo-url>
cd fraud-platform

cp .env.example .env
# Edit .env — at minimum generate a Fernet key for Airflow:
# python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### Start All Phases

```bash
make phase1-up   # Kafka, Schema Registry, Kafka UI, Producer
make phase2-up   # MinIO, Spark, Delta Lake streaming
make phase3-up   # Postgres, Trino, Airflow, dbt
make phase4-up   # MLflow, Redis, Fraud API
make phase5-up   # Prometheus, Grafana, Superset
```

Or start everything at once:
```bash
make up
```

### Run All Tests
```bash
make test
```

---

## Phase Breakdown

---

### Phase 1 — Data Ingestion

**Goal:** Get transactions flowing through Kafka with schema enforcement.

**What's built:**
- Python producer generating realistic payment transactions at configurable TPS (default 100/s)
- Avro schema registered in Schema Registry before any messages are sent
- Dead Letter Queue (DLQ) — bad messages are never dropped, they're routed to `transactions.dlq` for inspection
- 10 Kafka partitions enabling 10 parallel consumers
- Kafka UI for live topic monitoring

**Key files:**
- `phase1-ingestion/producer/schemas/transaction.avsc` — the data contract
- `phase1-ingestion/producer/producer.py` — transaction generator with DLQ routing

**What you learn:**
- Kafka topics, partitions, consumer groups
- Why Avro beats JSON for streaming (schema enforcement, compact binary encoding)
- Schema evolution and backward compatibility
- Dead letter queue pattern for fault-tolerant ingestion

**Validation:**
```bash
# See messages flowing
open http://localhost:8080         # Kafka UI → transactions.raw

# Check schema registered
curl http://localhost:8081/subjects
```

---

### Phase 2 — Streaming Pipeline & Lakehouse

**Goal:** Land every Kafka transaction into Delta Lake on MinIO with quality guarantees.

**What's built:**
- Spark Structured Streaming job reading `transactions.raw`
- Quality checks validate each row before landing (amount > 0, user_id not null, valid timestamp)
- Invalid rows routed to `transactions.dlq` — never dropped silently
- Delta Lake writes partitioned by `event_date` for efficient time-range queries
- Checkpointing to MinIO — crash-safe, exactly-once delivery

**Architecture decision — why Delta Lake:**
- ACID transactions: partial writes never appear to readers
- Time travel: query any previous version of the table
- Schema evolution: add columns without breaking existing readers
- Unified batch + streaming reads

**Key files:**
- `phase2-streaming/spark_jobs/bronze_writer.py` — main streaming job
- `phase2-streaming/spark_jobs/quality_checks.py` — validation rules

**What you learn:**
- Micro-batch streaming vs continuous processing
- Watermarking for late-arriving events
- Checkpointing and Kafka offset management
- Medallion architecture — why raw Bronze data is preserved unmodified
- Backpressure via `maxOffsetsPerTrigger`

**Validation:**
```bash
open http://localhost:9001          # MinIO → fraud-platform/bronze/transactions/
open http://localhost:8090          # Spark UI → active streaming query
```

---

### Phase 3 — Analytics Transformation Layer

**Goal:** Transform raw Bronze data into analytics-ready Silver and Gold layers. Schedule everything with Airflow.

**What's built:**
- Trino as the SQL query engine over Delta Lake files in MinIO
- dbt models across three layers:
  - **Staging** (Silver): type casts, renames — no business logic
  - **Intermediate** (Silver): merchant join, risk flags, 30-day rolling aggregations per user
  - **Marts** (Gold): ML feature table, hourly metrics, user risk profiles
- Airflow DAG running every 15 minutes: `bronze_freshness_check → dbt_seed → dbt_staging → dbt_intermediate → dbt_marts → dbt_test → push_features_to_redis`
- Custom dbt tests: fraud rate sanity check, no-future-events guard
- `merchants.csv` seed — reference data joined to every transaction

**Medallion layer mapping:**

| Layer | Trino Schema | What it contains |
|---|---|---|
| Bronze | `delta.bronze` | Raw Spark-written Parquet |
| Silver | `delta.silver` | Typed views: stg_transactions, int_enriched, int_velocity |
| Gold | `delta.gold` | Incremental tables: mart_fraud_features, mart_hourly_metrics, mart_user_risk_profiles |

**Key design: why incremental materialization**
Mart models use `incremental` (INSERT INTO) rather than `table` (CREATE + rename) because MinIO/S3 does not support atomic directory rename. Incremental writes are safe and idempotent via `unique_key`.

**Key files:**
- `phase3-transforms/dbt_project/models/` — all SQL transforms
- `phase3-transforms/airflow/dags/fraud_pipeline.py` — orchestration DAG
- `infra/trino/catalog/delta.properties` — connects Trino to MinIO

**What you learn:**
- dbt materializations: view vs table vs incremental
- Incremental models: `is_incremental()`, `unique_key`, schema change handling
- Airflow DAG dependencies, retries, SLA monitoring
- Trino as a query federation layer — SQL over files without moving data
- Semantic layer: defining metrics as code, not in dashboards

**Validation:**
```bash
open http://localhost:8082          # Airflow → fraud_pipeline DAG running
docker compose exec trino trino --execute \
  "SELECT COUNT(*) FROM delta.bronze_marts.mart_fraud_features"
```

---

### Phase 4 — ML Deployment

**Goal:** Train a fraud classifier, register it, and serve real-time predictions through a production API.

**What's built:**
- **Training pipeline:** RandomForest trained on `mart_fraud_features` (30-day user behaviour features). Logs to MLflow. Auto-promotes to Staging if AUC ≥ 0.90
- **MLflow model registry:** None → Staging → Production → Archived lifecycle. Model artifacts stored in MinIO
- **Redis feature store:** `feature_writer.py` pushes user feature vectors to Redis after every dbt Gold run. Keys expire after 24h
- **FastAPI `/predict`:** Looks up user features from Redis (< 1ms), scores with loaded model, returns `fraud_probability`, `risk_tier`, `model_version`, `latency_ms`
- **Circuit breaker:** Redis timeout or failure → fallback to safe defaults. API never goes down due to cache failure
- **Prediction logging:** Every prediction written to Postgres `predictions` table for audit and retraining

**The train-serve skew problem — and the solution:**
`features.py` is a single shared file imported by both `train.py` and `feature_client.py`. The same `UserFeatures.to_array()` method computes features identically in training and serving. This is enforced at the Docker build level — the Dockerfile copies the root `features.py` into the serving container.

**Feature pipeline:**
```
Gold: mart_fraud_features (Trino)
    ↓ feature_writer.py (every 15 min)
Redis: user_features:{user_id} = JSON blob
    ↓ feature_client.py (every /predict call)
UserFeatures.to_array() → numpy array → RandomForest → float
```

**Key files:**
- `phase4-ml/features.py` — shared feature definitions (the contract)
- `phase4-ml/training/train.py` — MLflow-instrumented training
- `phase4-ml/serving/main.py` — FastAPI endpoints
- `phase4-ml/serving/predictor.py` — model loader + scorer
- `phase4-ml/serving/feature_client.py` — Redis lookup with fallback
- `phase4-ml/serving/feature_writer.py` — Gold → Redis writer

**What you learn:**
- MLflow: experiment tracking, artifact storage, model registry stages
- Train-serve skew: why shared feature code is non-negotiable
- Circuit breaker pattern for cache-dependent services
- Redis as a feature store: memory-first, key-value, sub-millisecond reads
- FastAPI: async endpoints, Pydantic models, startup events

**Validation:**
```bash
open http://localhost:5000          # MLflow → fraud_classifier in Production

curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"transaction_id":"t1","user_id":"U1234","amount":500,
       "merchant_id":"M001","is_international":false}'

# Kill Redis → API still responds (fallback)
docker compose stop redis
curl -X POST http://localhost:8000/predict ...  # still works
docker compose start redis
```

---

### Phase 5 — Analytics Layer & Production Hardening

**Goal:** Full observability stack live. Dashboards for operations and business. System hardened for reliability.

**What's built:**
- **Prometheus:** Scrapes `fraud-api /metrics` (prediction counters, latency histograms) and `kafka-exporter` (topic message rates, consumer lag, DLQ counts)
- **Grafana dashboards:**
  - *Pipeline Health:* Kafka messages/sec, consumer lag per partition, DLQ alert, Bronze table freshness
  - *ML Monitoring:* Prediction volume, P50/P95/P99 latency, fraud rate trend, Redis cache hit rate, model version in production
- **Superset:** Connected to Trino, queries Gold tables directly. Three dashboards: Transaction Overview, Fraud Analytics, Real-Time Risk Feed
- **kafka-exporter:** Sidecar that exposes Kafka broker and consumer group metrics in Prometheus format

**Instrumentation in fraud-api:**
```
fraud_predictions_total{risk_tier}    — counter, predictions by risk level
fraud_prediction_latency_seconds      — histogram, P50/P95/P99 available
fraud_model_version                   — gauge, currently loaded model version
fraud_redis_cache_hits_total          — counter, cache vs fallback ratio
```

**Alerting philosophy — alert on symptoms, not causes:**
- DLQ count > 0 in 5 min window → pipeline data quality issue
- API error rate > 1% → serving reliability issue
- Fraud rate > 2x 7-day baseline → model drift or attack pattern

**What you learn:**
- Prometheus pull model: scrape intervals, labels, metric types (counter, gauge, histogram)
- Grafana: datasource provisioning, dashboard-as-code, alert rules
- Four golden signals: latency, traffic, errors, saturation
- Model drift detection: when to alert vs when to retrain
- Superset semantic layer: define datasets once, analysts self-serve

**Validation:**
```bash
open http://localhost:9090/targets    # Prometheus → all targets UP
open http://localhost:3000            # Grafana → both dashboards with data
open http://localhost:8088            # Superset → SQL Lab against Gold tables

# Trigger alert: flood DLQ
for i in {1..50}; do
  docker compose exec kafka kafka-console-producer \
    --bootstrap-server localhost:29092 --topic transactions.dlq <<< "bad-message-$i"
done
```

---

## Makefile Reference

```bash
make up              # Start all services
make down            # Stop all services
make clean           # Stop + remove all volumes (destructive)
make build           # Rebuild all images

make phase1-up       # Start Phase 1 services only
make phase2-up       # Start Phase 2 services only
make phase3-up       # Start Phase 3 services only
make phase4-up       # Start Phase 4 services only
make phase5-up       # Start Phase 5 services only

make test            # Run all phase tests
make phase1-test     # Phase 1 unit tests (inside Docker)
make phase2-test     # Phase 2 Spark tests (inside Docker)
make phase3-test     # dbt schema + custom tests
make phase4-test     # ML feature + serving tests

make ml-train        # Trigger a training run
make predict-test    # Send one test prediction to fraud-api
make dbt-run         # Run dbt seed + run manually
make dbt-test        # Run dbt tests manually
make kafka-lag       # Show consumer group lag
make redis-features  # List Redis feature keys
```

---

## Key Design Decisions

**Why Avro over JSON?**
Schema enforcement at write time, not read time. The Schema Registry rejects malformed messages before they enter the pipeline. Avro binary encoding is ~30% smaller than equivalent JSON.

**Why Delta Lake over raw Parquet?**
ACID transactions mean partial writes never appear to readers. Time travel enables point-in-time recovery. Schema evolution is non-breaking. Spark and Trino both read Delta natively.

**Why dbt over raw SQL scripts?**
Dependency management, incremental materialisation, built-in testing, and a semantic layer. `dbt test` runs 30+ data quality assertions on every pipeline run. SQL is version-controlled and peer-reviewable.

**Why Redis for the feature store?**
A Trino query over Parquet files takes 300–2000ms. Redis GET is < 1ms. At 500 predictions/sec, that's the difference between a usable API and a non-starter. Gold tables remain the source of truth; Redis is the speed layer.

**Why share features.py between training and serving?**
Train-serve skew is one of the most common sources of ML model degradation in production. If the feature engineering code diverges between training and serving, the model sees different inputs at inference time than it was trained on. Sharing one file makes this divergence impossible at the code level.

---

## Skills Demonstrated

- **Streaming:** Kafka partitioning, consumer groups, Schema Registry, DLQ patterns
- **Lakehouse:** Delta Lake ACID writes, checkpointing, watermarking, medallion architecture
- **Data Modelling:** dbt staging/intermediate/mart separation, incremental models, semantic layer
- **Orchestration:** Airflow DAG design, task dependencies, retry policies
- **ML Engineering:** MLflow tracking, model registry, feature stores, prediction logging
- **API Design:** FastAPI, circuit breakers, fallback patterns, Prometheus instrumentation
- **Observability:** Four golden signals, alert-on-symptoms philosophy, dashboard-as-code
- **Infrastructure:** Docker Compose multi-network, health checks, volume management
