insert into "delta"."bronze_marts"."mart_user_risk_profiles" ("user_id", "tx_count_30d", "avg_amount_30d", "max_amount_30d", "unique_devices_30d", "unique_countries_30d", "intl_tx_count_30d", "high_amount_count_30d", "last_tx_at", "feature_updated_at", "risk_tier")
    (
        select "user_id", "tx_count_30d", "avg_amount_30d", "max_amount_30d", "unique_devices_30d", "unique_countries_30d", "intl_tx_count_30d", "high_amount_count_30d", "last_tx_at", "feature_updated_at", "risk_tier"
        from "delta"."bronze_marts"."mart_user_risk_profiles__dbt_tmp"
    )

