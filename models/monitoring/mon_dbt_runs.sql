{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='log_id',
    on_schema_change='fail',
    partition_by={'field': 'logged_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['node_name'],
) }}

-- One row per model or test result of every dbt run, from dbt's JSON logs (--log-format json).
with events as (
    select
        insertId as log_id,
        timestamp as logged_at,
        labels.run_googleapis_com_execution_name as execution_name,
        jsonPayload.info.invocation_id as invocation_id,
        jsonPayload.info.name as event,
        jsonPayload.data.node_info.unique_id as unique_id,
        jsonPayload.data.node_info.node_status as status,
        jsonPayload.data.execution_time as execution_time_seconds,
        jsonPayload.data.num_failures as num_failures,
        jsonPayload.info.msg as message
    from {{ source('bronze', 'run_googleapis_com_stdout') }}
    where resource.labels.job_name = 'pbk-dbt'
        and jsonPayload.info.name in ('LogModelResult', 'LogTestResult')
        {% if is_incremental() %}
        and timestamp >= (select timestamp_sub(max(logged_at), interval 1 hour) from {{ this }})
        {% endif %}
    -- the sink can deliver the same log entry more than once
    qualify row_number() over (partition by insertId order by timestamp) = 1
)

select
    log_id,
    logged_at,
    execution_name,
    invocation_id,
    if(event = 'LogTestResult', 'test', 'model') as node_type,
    unique_id,
    split(unique_id, '.')[safe_offset(2)] as node_name,
    status,
    status in ('error', 'fail') as is_failure,
    execution_time_seconds,
    num_failures,
    regexp_replace(message, r'\x1b\[[0-9;]*m', '') as message
from events
