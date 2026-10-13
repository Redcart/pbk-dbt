-- One row per bike present at a station per snapshot.
select
    snapshot_id,
    observed_at,
    ingested_at,
    json_value(station, '$.station_id') as station_id,
    json_value(bike, '$.bike_id') as bike_id,
    json_value(bike, '$.range') as bike_range
from {{ source('bronze', 'publibike_snapshots') }},
    unnest(json_query_array(payload, '$.stations')) as station,
    unnest(json_query_array(station, '$.status.bikes')) as bike
