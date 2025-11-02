with

src_capacity as (

  select
    station_id,
    TIMESTAMP_TRUNC(ingestion_time, MINUTE) as ingestion_time,
    vehicle_type_id
  from {{ source('src_api_pbk', 'capacity') }}

)

select
    *
from src_capacity
