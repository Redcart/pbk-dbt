with

list_stations as (

  select distinct
    station_id
  from {{ ref('stg_api_publibike__stations') }}

),

bikes_capacity as (

  select
    station_id,
    ingestion_time,
    vehicle_type_id
  from {{ ref('stg_api_publibike__capacity') }}

),

list_timestamp as (

  select
    ingestion_time
  from
    UNNEST(
      GENERATE_TIMESTAMP_ARRAY(
        TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 55 MINUTE),
        TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR),
      INTERVAL 5 MINUTE)
    ) as ingestion_time

),

list_stations_timestamp as (

  select
    list_stations.station_id,
    list_timestamp.ingestion_time
  from list_stations
  cross join list_timestamp

),

available_mechanic_bikes as (

  select
    station_id,
    ingestion_time,
    vehicle_type_id,
    count(*) as nb_bikes_available_mechanic
  from bikes_capacity
  where vehicle_type_id = "1"
  group by station_id, vehicle_type_id, ingestion_time

),

available_electric_bikes as (

  select
    station_id,
    ingestion_time,
    vehicle_type_id,
    count(*) as nb_bikes_available_electric
  from bikes_capacity
  where vehicle_type_id = "2"
  group by station_id, vehicle_type_id, ingestion_time

),

stations_with_nb_available_bikes as (

  select
    list_stations_timestamp.station_id,
    list_stations_timestamp.ingestion_time,
    COALESCE(nb_bikes_available_mechanic, 0) as nb_bikes_available_mechanic,
    COALESCE(nb_bikes_available_electric, 0) as nb_bikes_available_electric,
    COALESCE(nb_bikes_available_mechanic, 0) + COALESCE(nb_bikes_available_electric, 0) as nb_bikes_available
  from list_stations_timestamp
  left join available_mechanic_bikes
  on list_stations_timestamp.station_id = available_mechanic_bikes.station_id
  and list_stations_timestamp.ingestion_time = available_mechanic_bikes.ingestion_time
  left join available_electric_bikes
  on list_stations_timestamp.station_id = available_electric_bikes.station_id
  and list_stations_timestamp.ingestion_time = available_electric_bikes.ingestion_time

)

select
  station_id,
  ingestion_time,
  nb_bikes_available_mechanic,
  nb_bikes_available_electric,
  nb_bikes_available
from stations_with_nb_available_bikes
--ORDER BY station_id, ingestion_time DESC
