with

src_stations as (

  select
    station_id,
    name,
    TIMESTAMP_TRUNC(ingestion_time, MINUTE) as ingestion_time
  from {{ source('src_api_pbk', 'stations') }}
)

select
    *
from src_stations
