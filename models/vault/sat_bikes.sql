{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['bike_hk', 'observed_at'],
    on_schema_change='fail',
    partition_by={'field': 'observed_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['bike_hk'],
) }}

with src as (
    select
        {{ hash_key(['bike_id']) }} as bike_hk,
        bike_id,
        observed_at,
        ingested_at,
        bike_range,
        {{ hashdiff(['bike_range']) }} as hashdiff
    from {{ ref('stg_station_bikes') }}
    where {{ vault_window() }}
    qualify row_number() over (partition by bike_id, snapshot_id order by station_id) = 1
),

changes as (
    select
        *,
        lag(hashdiff) over (partition by bike_hk order by observed_at) as prev_hashdiff
    from src
)

{% if is_incremental() %}
, latest as (
    select bike_hk, hashdiff as last_hashdiff
    from {{ this }}
    qualify row_number() over (partition by bike_hk order by observed_at desc) = 1
)
{% endif %}

select changes.* except (prev_hashdiff)
from changes
{% if is_incremental() %}
left join latest using (bike_hk)
{% endif %}
where hashdiff is distinct from coalesce(prev_hashdiff{% if is_incremental() %}, last_hashdiff{% endif %})
