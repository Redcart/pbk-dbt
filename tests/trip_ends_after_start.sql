select * from {{ ref('fct_trips') }} where ended_at < started_at
