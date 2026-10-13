{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='station_bike_hk',
    on_schema_change='fail',
) }}

select
    {{ hash_key(['station_id', 'bike_id']) }} as station_bike_hk,
    {{ hash_key(['station_id']) }} as station_hk,
    {{ hash_key(['bike_id']) }} as bike_hk,
    station_id,
    bike_id,
    min(observed_at) as first_seen_at,
    min(ingested_at) as ingested_at,
    'publibike' as record_source
from {{ ref('stg_station_bikes') }}
where {{ vault_window('first_seen_at') }}
group by station_bike_hk, station_hk, bike_hk, station_id, bike_id
{% if is_incremental() %}
having station_bike_hk not in (select station_bike_hk from {{ this }})
{% endif %}
