-- Current network: stations whose latest state is active.
with latest as (
    select *
    from {{ ref('sat_stations') }}
    qualify row_number() over (partition by station_hk order by observed_at desc) = 1
)

select
    hub.station_id,
    latest.station_number,
    latest.station_name,
    latest.station_address,
    latest.latitude,
    latest.longitude,
    latest.details_route,
    hub.first_seen_at,
    latest.observed_at as last_changed_at
from {{ ref('hub_stations') }} as hub
inner join latest using (station_hk)
where latest.status = 'active'
