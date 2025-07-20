SELECT
  SUM(nb_bikes_available_mechanic) AS sum_nb_bikes_available_mechanic,
  SUM(nb_bikes_available_electric) AS sum_nb_bikes_available_electric,
  SUM(nb_bikes_available) AS sum_nb_bikes_available,
  ingestion_time
FROM  `{{ project_id }}.{{ dataset }}.{{ table_stations }}`
GROUP BY ingestion_time
ORDER BY ingestion_time
