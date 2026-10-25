-- dbt's own JSON logs (Cloud Run job `dbt_job_name`, run with --log-format json): one row per model or test result.
-- The Cloud Logging sink can deliver an entry more than once (same log_id): dedupe downstream, after filtering on
-- logged_at, so the filter prunes the partitions.
select
    insertId as log_id,
    timestamp as logged_at,
    labels.run_googleapis_com_execution_name as execution_name,
    jsonPayload.info.invocation_id as invocation_id,
    if(jsonPayload.info.name = 'LogTestResult', 'test', 'model') as node_type,
    jsonPayload.data.node_info.unique_id as unique_id,
    jsonPayload.data.node_info.node_status as status,
    jsonPayload.data.execution_time as execution_time_seconds,
    jsonPayload.data.num_failures as num_failures,
    regexp_replace(jsonPayload.info.msg, r'\x1b\[[0-9;]*m', '') as message
from {{ source('bronze', 'run_googleapis_com_stdout') }}
where resource.labels.job_name = '{{ var("dbt_job_name") }}'
    and jsonPayload.info.name in ('LogModelResult', 'LogTestResult')
