with

capacity_over_time as (

select
  nb_bikes_available_mechanic,
  nb_bikes_available_electric,
  nb_bikes_available,
  ingestion_time
from {{ ref('bikes_over_time') }}

),

bikes_agregated as (

select
  sum(nb_bikes_available_mechanic) as sum_nb_bikes_available_mechanic,
  sum(nb_bikes_available_electric) as sum_nb_bikes_available_electric,
  sum(nb_bikes_available) as sum_nb_bikes_available,
  ingestion_time
from capacity_over_time
group by ingestion_time

)

select
    sum_nb_bikes_available_mechanic,
    sum_nb_bikes_available_electric,
    sum_nb_bikes_available,
    ingestion_time
from bikes_agregated
