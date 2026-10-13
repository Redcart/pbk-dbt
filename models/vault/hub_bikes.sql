{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='bike_hk',
    on_schema_change='fail',
) }}

select
    {{ hash_key(['bike_id']) }} as bike_hk,
    bike_id,
    min(observed_at) as first_seen_at,
    min(ingested_at) as ingested_at,
    'publibike' as record_source
from {{ ref('stg_station_bikes') }}
where {{ vault_window('first_seen_at') }}
group by bike_hk, bike_id
{% if is_incremental() %}
having bike_hk not in (select bike_hk from {{ this }})
{% endif %}
