-- One row per station per snapshot.
select
    snapshot_id,
    observed_at,
    ingested_at,
    json_value(station, '$.station_id') as station_id,
    json_value(station, '$.station_number') as station_number,
    json_value(station, '$.station_name') as station_name,
    json_value(station, '$.station_address') as station_address,
    lax_float64(json_query(station, '$.lat')) as latitude,
    lax_float64(json_query(station, '$.lng')) as longitude,
    json_value(station, '$.details_route') as details_route,
    lax_int64(json_query(station, '$.status.total_bikes')) as total_bikes,
    lax_int64(json_query(station, '$.status.total_non_electrical_bikes')) as total_non_electrical_bikes,
    lax_int64(json_query(station, '$.status.total_electrical_bikes')) as total_electrical_bikes
from {{ source('bronze', 'publibike_snapshots') }},
    unnest(json_query_array(payload, '$.stations')) as station
