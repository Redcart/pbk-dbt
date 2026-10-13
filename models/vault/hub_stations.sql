{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='station_hk',
    on_schema_change='fail',
) }}

select
    {{ hash_key(['station_id']) }} as station_hk,
    station_id,
    min(observed_at) as first_seen_at,
    min(ingested_at) as ingested_at,
    'publibike' as record_source
from {{ ref('stg_stations') }}
where {{ vault_window('first_seen_at') }}
group by station_hk, station_id
{% if is_incremental() %}
having station_hk not in (select station_hk from {{ this }})
{% endif %}
