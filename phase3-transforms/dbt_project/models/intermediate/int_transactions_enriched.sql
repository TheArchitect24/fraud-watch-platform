-- Silver: join merchant reference data, add risk classification flags.

with txs as (
    select * from {{ ref('stg_transactions') }}
),

merchants as (
    select * from {{ ref('merchants') }}
),

enriched as (
    select
        t.*,
        coalesce(m.category, 'unknown') as merchant_category,
        coalesce(m.risk_tier, 'medium') as merchant_risk_tier,
        case
            when t.amount > 2000 then 'high'
            when t.amount > 500  then 'medium'
            else  'low'
        end  as amount_risk_tier,
        case
            when t.is_international
             and t.amount > 500 then true
            else false
        end as is_high_risk_international
    from txs t
    left join merchants m on t.merchant_id = m.merchant_id
)

select * from enriched
