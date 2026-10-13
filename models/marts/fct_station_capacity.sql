{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='station_snapshot_hk',
    on_schema_change='fail',
    partition_by={'field': 'observed_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['station_id'],
) }}

-- Bikes available per station and snapshot.
select
    {{ hash_key(['station_id', 'snapshot_id']) }} as station_snapshot_hk,
    snapshot_id,
    station_id,
    observed_at,
    ingested_at,
    total_bikes as bikes_available,
    total_electrical_bikes as electric_bikes_available,
    total_non_electrical_bikes as standard_bikes_available
from {{ ref('stg_stations') }}
where {{ vault_window() }}
