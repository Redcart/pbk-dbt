{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['station_bike_hk', 'observed_at'],
    on_schema_change='fail',
    partition_by={'field': 'observed_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['station_hk'],
) }}

-- Effectivity of the station-bike link: 'active' when the bike shows up at the station,
-- 'closed' when it is gone from that station (rented, moved) in the next snapshot.
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
        {{ hash_key(['station_id', 'bike_id']) }} as station_bike_hk,
        {{ hash_key(['station_id']) }} as station_hk,
        {{ hash_key(['bike_id']) }} as bike_hk,
        observed_at,
        ingested_at,
        'active' as status
    from {{ ref('stg_station_bikes') }}
    where {{ vault_window() }}
),

closed as (
    select
        present.station_bike_hk,
        present.station_hk,
        present.bike_hk,
        snapshots.next_observed_at as observed_at,
        snapshots.next_ingested_at as ingested_at,
        'closed' as status
    from present
    inner join snapshots on snapshots.observed_at = present.observed_at
    where snapshots.next_observed_at is not null
        and not exists (
            select 1 from present as later
            where later.station_bike_hk = present.station_bike_hk
                and later.observed_at = snapshots.next_observed_at
        )
),

events as (
    select * from present
    union all
    select * from closed
),

changes as (
    select
        *,
        lag(status) over (partition by station_bike_hk order by observed_at) as prev_status
    from events
)

{% if is_incremental() %}
, latest as (
    select station_bike_hk, status as last_status
    from {{ this }}
    qualify row_number() over (partition by station_bike_hk order by observed_at desc) = 1
)
{% endif %}

select changes.* except (prev_status)
from changes
{% if is_incremental() %}
left join latest using (station_bike_hk)
{% endif %}
where status is distinct from coalesce(prev_status{% if is_incremental() %}, last_status{% endif %})
