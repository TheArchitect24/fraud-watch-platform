-- Gold: user-level features for ML model training and serving.
-- One row per user_id. Refreshed incrementally every 15 min via Airflow.

{{
    config(
        materialized='incremental',
        unique_key='user_id',
        on_schema_change='sync_all_columns'
    )
}}

with velocity as (
    select * from {{ ref('int_user_velocity') }}
    {% if is_incremental() %}
    where last_tx_at > (select max(feature_updated_at) from {{ this }})
    {% endif %}
)

select
    user_id,
    tx_count_30d,
    avg_amount_30d,
    stddev_amount_30d,
    max_amount_30d,
    unique_devices_30d,
    unique_countries_30d,
    intl_tx_count_30d,
    high_amount_count_30d,
    last_tx_at,
    current_timestamp  as feature_updated_at
from velocity
