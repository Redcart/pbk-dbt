{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='trip_hk',
    on_schema_change='fail',
    partition_by={'field': 'started_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['start_station_id', 'bike_id'],
) }}

-- A trip is a bike leaving a station (its `closed` event) followed by the same bike showing up at a station
-- (its next `active` event). Times are snapshot times, so they are accurate to one snapshot (5 minutes):
-- started_at is the first snapshot without the bike, ended_at the first snapshot with it again.
-- Bikes not yet returned are not trips yet. Incremental runs look back 7 days for the departure of a returning
-- bike; a longer rental is only picked up by a full refresh.
with events as (
    select
        link.bike_id,
        link.station_id,
        eff.bike_hk,
        eff.status,
        eff.observed_at,
        eff.ingested_at
    from {{ ref('sat_station_bike_eff') }} as eff
    inner join {{ ref('lnk_station_bike') }} as link using (station_bike_hk)
    {% if is_incremental() %}
    where eff.observed_at >= (select timestamp_sub(max(ended_at), interval 7 day) from {{ this }})
    {% endif %}
),

sequenced as (
    select
        *,
        lead(status) over bike_timeline as next_status,
        lead(station_id) over bike_timeline as next_station_id,
        lead(observed_at) over bike_timeline as next_observed_at,
        lead(ingested_at) over bike_timeline as next_ingested_at
    from events
    -- at equal times, the departure comes before the arrival
    window bike_timeline as (partition by bike_hk order by observed_at, if(status = 'closed', 0, 1))
)

select
    {{ hash_key(['bike_id', 'observed_at']) }} as trip_hk,
    bike_id,
    station_id as start_station_id,
    next_station_id as end_station_id,
    observed_at as started_at,
    next_observed_at as ended_at,
    timestamp_diff(next_observed_at, observed_at, minute) as duration_minutes,
    next_ingested_at as ingested_at
from sequenced
where status = 'closed'
    and next_status = 'active'
    {% if is_incremental() %}
    and next_ingested_at >= (select max(ingested_at) from {{ this }})
    {% endif %}
