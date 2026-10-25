-- One row per pipeline run: 
-- Cloud Run Job executions (extract, dbt)
-- Load Cloud Run function requests
with cloud_run_job_executions as (
    select
        'cloud run job' as run_type,
        job_name as pipeline,
        execution_name as run_id,
        occurred_at,
        message as detail,
        is_success
    from {{ ref('stg_cloud_run_job_events') }}
),

cloud_run_function_executions as (
    select
        'cloud run function' as run_type,
        function_name as pipeline,
        log_id as run_id,
        occurred_at,
        concat('HTTP ', cast(http_status as string)) as detail,
        is_success
    from {{ ref('stg_cloud_run_function_events') }}
)

select
    *,
    if(is_success, 'success', 'failure') as status
from cloud_run_job_executions
union all
select
    *,
    if(is_success, 'success', 'failure') as status
from cloud_run_function_executions
