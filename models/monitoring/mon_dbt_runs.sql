{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='log_id',
    on_schema_change='fail',
    partition_by={'field': 'logged_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['node_name'],
) }}

-- One row per model or test result of every dbt run.
select
    log_id,
    logged_at,
    execution_name,
    invocation_id,
    node_type,
    unique_id,
    split(unique_id, '.')[safe_offset(2)] as node_name,
    status,
    status in ('error', 'fail') as is_failure,
    execution_time_seconds,
    num_failures,
    message
from {{ ref('stg_dbt_log_events') }}
{% if is_incremental() %}
where logged_at >= (select timestamp_sub(max(logged_at), interval 1 hour) from {{ this }})
{% endif %}
-- the sink can deliver the same log entry more than once
qualify row_number() over (partition by log_id order by logged_at) = 1
