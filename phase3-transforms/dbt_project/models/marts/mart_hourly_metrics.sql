-- Gold: hour-bucketed pipeline metrics for operational dashboards.
-- Incremental to avoid S3A directory-rename limitation with table materialization.

{{
    config(
        materialized='incremental',
        unique_key='hour_bucket',
        on_schema_change='sync_all_columns'
    )
}}

with enriched as (
    select * from {{ ref('int_transactions_enriched') }}
),

hourly as (
    select
        date_trunc('hour', event_at)  as hour_bucket,
        count(*) as tx_count,
        sum(amount) as total_amount,
        avg(amount) as avg_amount,
        count(distinct user_id) as unique_users,
        count(distinct merchant_id) as unique_merchants,
        sum(case when is_international then 1 else 0 end)   as intl_count,
        sum(case when amount_risk_tier = 'high' then 1 else 0 end) as high_risk_count,
        -- fraud_rate placeholder: populated once labels table exists
        cast(0.0 as double)                                 as fraud_rate
    from enriched
    group by 1
)

select * from hourly
order by hour_bucket desc
