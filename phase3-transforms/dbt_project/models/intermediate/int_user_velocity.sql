-- Rolling window velocity signals per user: tx count, amount stats, device/country spread.
-- Lookback window is 30 days from the most recent event in the batch.

with enriched as (
    select * from {{ ref('int_transactions_enriched') }}
),

windowed as (
    select
        user_id,
        count(*) as tx_count_30d,
        avg(amount) as avg_amount_30d,
        stddev(amount) as stddev_amount_30d,
        max(amount) as max_amount_30d,
        count(distinct device_id) as unique_devices_30d,
        count(distinct country) as unique_countries_30d,
        sum(case when is_international then 1 else 0 end) as intl_tx_count_30d,
        sum(case when amount_risk_tier = 'high' then 1 else 0 end) as high_amount_count_30d,
        max(event_at) as last_tx_at
    from enriched
    where event_at >= current_timestamp - interval '30' day
    group by user_id
)

select * from windowed
