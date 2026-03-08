"""
Fraud platform analytics pipeline.
Runs every 15 min: check bronze freshness → dbt staging → intermediate → marts → test.
"""
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

DBT_DIR = "/opt/dbt"
DBT_CMD = f"--profiles-dir {DBT_DIR} --project-dir {DBT_DIR}"

default_args = {
    "owner": "analytics-eng",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="fraud_pipeline",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="*/15 * * * *",
    catchup=False,
    tags=["fraud", "dbt"],
) as dag:

    check_bronze_freshness = BashOperator(
        task_id="check_bronze_freshness",
        bash_command="""
            python3 -c "
import trino, sys
conn = trino.dbapi.connect(host='trino', port=8080, user='airflow', catalog='delta', schema='bronze')
cur = conn.cursor()
cur.execute('SELECT max(loaded_at) FROM transactions')
row = cur.fetchone()
if row[0] is None:
    print('ERROR: bronze table empty', flush=True)
    sys.exit(1)
from datetime import datetime, timezone, timedelta
age = datetime.now(timezone.utc) - row[0].replace(tzinfo=timezone.utc)
if age > timedelta(seconds=300):
    print(f'ERROR: bronze stale by {age}', flush=True)
    sys.exit(1)
print(f'Bronze fresh: last write {age} ago', flush=True)
"
        """,
    )

    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command=f"dbt seed {DBT_CMD}",
    )

    dbt_staging = BashOperator(
        task_id="dbt_staging",
        bash_command=f"dbt run --select staging {DBT_CMD}",
    )

    dbt_intermediate = BashOperator(
        task_id="dbt_intermediate",
        bash_command=f"dbt run --select intermediate {DBT_CMD}",
    )

    dbt_marts = BashOperator(
        task_id="dbt_marts",
        bash_command=f"dbt run --select marts {DBT_CMD}",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"dbt test {DBT_CMD}",
    )

    (
        check_bronze_freshness
        >> dbt_seed
        >> dbt_staging
        >> dbt_intermediate
        >> dbt_marts
        >> dbt_test
    )
