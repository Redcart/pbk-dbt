-- Every bike ever seen, with its latest range and the station it is at now (null while rented).
with latest_attributes as (
    select *
    from {{ ref('sat_bikes') }}
    qualify row_number() over (partition by bike_hk order by observed_at desc) = 1
),

latest_presence as (
    select *
    from {{ ref('sat_station_bike_eff') }}
    qualify row_number() over (partition by station_bike_hk order by observed_at desc) = 1
),

current_station as (
    select
        link.bike_hk,
        link.station_id
    from latest_presence
    inner join {{ ref('lnk_station_bike') }} as link using (station_bike_hk)
    where latest_presence.status = 'active'
)

select
    hub.bike_id,
    latest_attributes.bike_range,
    current_station.station_id as current_station_id,
    current_station.station_id is not null as is_available,
    hub.first_seen_at
from {{ ref('hub_bikes') }} as hub
left join latest_attributes using (bike_hk)
left join current_station using (bike_hk)
