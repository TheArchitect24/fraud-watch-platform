insert into "delta"."bronze_marts"."mart_hourly_metrics" ("hour_bucket", "tx_count", "total_amount", "avg_amount", "unique_users", "unique_merchants", "intl_count", "high_risk_count", "fraud_rate")
    (
        select "hour_bucket", "tx_count", "total_amount", "avg_amount", "unique_users", "unique_merchants", "intl_count", "high_risk_count", "fraud_rate"
        from "delta"."bronze_marts"."mart_hourly_metrics__dbt_tmp"
    )

