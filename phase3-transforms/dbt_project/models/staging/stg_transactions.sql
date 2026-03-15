-- Minimal staging: type casts, renames, source filter only.
-- No business logic here.

with source as (
    select * from {{ source('bronze', 'transactions') }}
),

typed as (
    select
        transaction_id,
        user_id,
        cast(amount as decimal(18, 2)) as amount,
        upper(currency) as currency,
        merchant_id,
        lower(trim(merchant_name)) as merchant_name,
        upper(country) as country,
        city,
        device_id,
        device_type,
        from_unixtime(event_time / 1000) as event_at,
        cast(is_international as boolean) as is_international,
        date(from_unixtime(event_time / 1000)) as event_date,
        loaded_at
    from source
    where transaction_id is not null
      and amount > 0
)

select * from typed
