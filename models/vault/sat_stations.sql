{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['station_hk', 'observed_at'],
    on_schema_change='fail',
    partition_by={'field': 'observed_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['station_hk'],
) }}

{%- set attributes = ['station_number', 'station_name', 'station_address', 'latitude', 'longitude', 'details_route'] %}

with snapshots as (
    select
        observed_at,
        lead(observed_at) over (order by observed_at) as next_observed_at,
        lead(ingested_at) over (order by observed_at) as next_ingested_at
    from {{ ref('stg_snapshots') }}
    where {{ vault_window() }}
),

present as (
    select
        {{ hash_key(['station_id']) }} as station_hk,
        station_id,
        observed_at,
        ingested_at,
        {{ attributes | join(', ') }},
        'active' as status
    from {{ ref('stg_stations') }}
    where {{ vault_window() }}
),

-- a station present in a snapshot but absent from the next one is closed as of that next snapshot
closed as (
    select
        present.station_hk,
        present.station_id,
        snapshots.next_observed_at as observed_at,
        snapshots.next_ingested_at as ingested_at,
        {% for a in attributes %}present.{{ a }}, {% endfor %}
        'closed' as status
    from present
    inner join snapshots on snapshots.observed_at = present.observed_at
    where snapshots.next_observed_at is not null
        and not exists (
            select 1 from present as later
            where later.station_hk = present.station_hk
                and later.observed_at = snapshots.next_observed_at
        )
),

events as (
    select * from present
    union all
    select * from closed
),

hashed as (
    select *, {{ hashdiff(['status'] + attributes) }} as hashdiff
    from events
),

changes as (
    select
        *,
        lag(hashdiff) over (partition by station_hk order by observed_at) as prev_hashdiff
    from hashed
)

{% if is_incremental() %}
, latest as (
    select station_hk, hashdiff as last_hashdiff
    from {{ this }}
    qualify row_number() over (partition by station_hk order by observed_at desc) = 1
)
{% endif %}

select changes.* except (prev_hashdiff)
from changes
{% if is_incremental() %}
left join latest using (station_hk)
{% endif %}
where hashdiff is distinct from coalesce(prev_hashdiff{% if is_incremental() %}, last_hashdiff{% endif %})
