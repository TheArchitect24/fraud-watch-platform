# Teardown — Fraud Detection Analytics Platform

A production-grade, 5-phase fraud detection system demonstrating the full data engineering and ML lifecycle: streaming ingestion, lakehouse storage, batch transformation, ML model training and serving, and full observability. The flagship portfolio project.

---

## Architecture Summary

| Phase | What It Does |
|---|---|
| **Phase 1 — Ingestion** | Python producer → Kafka (Avro) → Schema Registry → Dead Letter Queue |
| **Phase 2 — Streaming** | Spark Structured Streaming → quality checks → Delta Lake Bronze on MinIO |
| **Phase 3 — Transforms** | Airflow → dbt via Trino → Silver (stg, int) → Gold (features, metrics, risk) |
| **Phase 4 — ML** | Gold → `feature_writer` → Redis → FastAPI `/predict` ← MLflow Production model |
| **Phase 5 — Observability** | Prometheus + Grafana (pipeline health + ML monitoring) + Superset (business analytics) |

---

## Stack Choices & Rationale

| Component | Decision Rationale |
|---|---|
| **Apache Kafka + Avro + Schema Registry** | Avro enforces schema at write time, not read time. The Schema Registry rejects malformed messages before they enter the pipeline. Avro binary encoding is ~30% more compact than JSON — meaningful at high TPS. |
| **Delta Lake on MinIO** | ACID transactions prevent partial writes from appearing to readers. Time travel enables point-in-time recovery. Schema evolution is non-breaking. MinIO provides S3-compatible object storage without a cloud dependency. |
| **Spark Structured Streaming** | Micro-batch processing with watermarking for late events, checkpointing for crash-safe exactly-once delivery, and native Delta Lake write support. |
| **Trino as SQL engine** | Federated SQL over Delta Lake files without moving data. Decouples compute from storage. `dbt-trino` runs all transformation SQL through Trino, enabling the standard dbt workflow against a lakehouse. |
| **dbt (dbt-trino)** | Dependency management, incremental materialisation, 30+ built-in data quality tests per run, and a semantic layer. SQL is version-controlled and reviewable. |
| **Redis as feature store** | A Trino query over Parquet takes 300–2000ms. A Redis GET takes <1ms. At 500 predictions/sec, Redis is the only viable option. Gold tables remain source of truth; Redis is the speed layer. |
| **MLflow** | Experiment tracking, artifact storage on MinIO, and a model registry with lifecycle stages (None → Staging → Production → Archived). Auto-promotion to Staging when AUC ≥ 0.90. |
| **FastAPI** | Async endpoints, Pydantic request/response validation, startup events for model loading, and native Prometheus instrumentation. The correct Python framework for a high-throughput scoring API. |
| **Prometheus + Grafana** | Pull-based metrics scraping at configurable intervals. Four golden signals (latency, traffic, errors, saturation) instrumented on the fraud API and Kafka exporter. |

---

## Critical Design Decisions

### 1. Shared `features.py` — Eliminating Train-Serve Skew

`features.py` is a single file imported by both `train.py` and `feature_client.py`. The same `UserFeatures.to_array()` method computes features identically in training and serving. This is enforced at the Docker build level — the Dockerfile copies the root `features.py` into the serving container.

> **Why this matters:** Train-serve skew is one of the most common causes of ML model degradation in production. If feature engineering code diverges between training and serving, the model sees different inputs at inference time than it was trained on. Sharing one file makes this divergence impossible at the code level.

### 2. Dead Letter Queue — Never Drop Messages

Bad messages at both the producer level and the Spark quality check level are routed to `transactions.dlq`, not discarded. This preserves every event for inspection and replay, enabling root-cause analysis of data quality issues without data loss.

### 3. Incremental Materialisation on S3 — Not CREATE + Rename

Gold mart models use `incremental` (INSERT INTO) rather than `table` (CREATE + rename) because MinIO/S3 does not support atomic directory rename. Incremental writes are safe and idempotent via `unique_key` — a constraint that required a deliberate architecture decision rather than a default setting.

### 4. Circuit Breaker on Redis

The FastAPI serving layer implements a circuit breaker: if Redis times out or fails, the API falls back to safe defaults and continues serving predictions. The API is never taken down by a cache failure. This is a production reliability pattern, not a convenience feature.

### 5. Alert on Symptoms, Not Causes

Grafana alerts are defined on observable symptoms: DLQ count > 0 (data quality issue), API error rate > 1% (serving reliability), fraud rate > 2x 7-day baseline (model drift or attack). Alerting on causes generates noise; alerting on symptoms forces focus on user-visible impact.

---

## Trade-offs

| Decision | Benefit | Cost |
|---|---|---|
| Delta Lake over Iceberg / Hudi | Native Spark integration, mature ecosystem, Trino Delta connector available | Iceberg has broader multi-engine support; Hudi has better CDC capabilities for OLTP-style workloads |
| RandomForest over XGBoost / LightGBM | Interpretable, no hyperparameter tuning required for a baseline, fast to train | Lower AUC ceiling; does not handle class imbalance as gracefully |
| Docker Compose over Kubernetes | Runs on a laptop, no cluster required, fast iteration | Not production-scalable; moving to k8s requires significant rework of service discovery and volumes |
| MinIO over cloud S3 | No cloud account required, fully local, S3-compatible API | Operational overhead of running a MinIO server; cloud S3 is managed and more reliable for production |
| FastAPI over Flask / Django | Async-native, Pydantic validation, OpenAPI docs auto-generated | Smaller ecosystem than Flask for general web development |
| Trino over Spark SQL for dbt | Dedicated SQL engine, lower latency for interactive queries, no Spark overhead for pure SQL | Additional service to operate; Spark SQL would be simpler if Spark is already in the stack |

---

## Extensions & Real-World Use Cases

### ML & Modelling

- Replace RandomForest with **XGBoost or LightGBM** and add class-weight balancing to address the inherent class imbalance in fraud datasets (typically <1% fraud rate).
- Implement **model monitoring**: log prediction distributions to Postgres and alert when they drift from the training distribution — a prerequisite for responsible production ML.
- Add an **online learning layer**: fine-tune the model on recent predictions without full retraining, reducing model staleness between weekly runs.
- Track **feature importance per MLflow run** to detect feature drift — when a previously important feature becomes less predictive over time.

### Data Platform

- Add a **Change Data Capture (CDC) layer** using Debezium to stream PostgreSQL prediction logs back into Kafka, closing the feedback loop from serving to the feature store.
- Replace `dbt-trino` with **`dbt-spark`** for organisations already operating a Spark cluster — the dbt model SQL is largely engine-agnostic.
- Add **data contracts between phases** using Avro schema evolution rules: a schema change in the producer must be backward-compatible with the Spark consumer before deployment.
- Extend the Airflow DAG with **sensors**: wait for Bronze table freshness before triggering dbt, and wait for Redis feature population before triggering scoring — making the pipeline event-driven rather than time-driven.

### Observability

- Add **distributed tracing (OpenTelemetry)** across the FastAPI serving layer and `feature_writer` to measure end-to-end latency from Gold table update to Redis write to prediction.
- Build a **model performance dashboard** in Superset: plot precision, recall, and AUC over time against the weekly training runs logged in MLflow.
- Add **Kafka consumer lag alerting at the partition level** — lag on a single partition can indicate a skewed key distribution affecting prediction freshness for a subset of users.

### Production Hardening

- Add **TLS and API key authentication** to the FastAPI endpoint before any external exposure.
- Implement a **canary deployment pattern** in MLflow promotion: route 5% of predictions to a Staging model and compare `fraud_probability` distributions before promoting to Production.
- Add a `make chaos` Makefile target that randomly stops Redis, Kafka, or the fraud API to test circuit breaker and fallback behaviour under failure conditions.

---

## Portfolio Signal

The Fraud Detection Platform is the clearest signal of engineering maturity in this portfolio. Every architectural decision — DLQ, shared `features.py`, incremental materialisation on S3, circuit breaker, symptom-based alerting — solves a specific class of production problem. The 5-phase structure also demonstrates the ability to plan and execute a large, multi-component system incrementally rather than all at once.
