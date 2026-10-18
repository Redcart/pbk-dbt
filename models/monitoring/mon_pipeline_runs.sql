-- One row per pipeline run: Cloud Run job executions (extract, dbt) and load function requests.
with job_executions as (
    select
        'job' as run_type,
        resource.labels.job_name as pipeline,
        regexp_extract(protopayload_auditlog.status.message, r'Execution (\S+) ') as run_id,
        timestamp as occurred_at,
        protopayload_auditlog.status.message as detail,
        regexp_contains(protopayload_auditlog.status.message, r'completed successfully') as is_success
    from {{ source('bronze', 'cloudaudit_googleapis_com_system_event') }}
    where protopayload_auditlog.methodName = '/Jobs.RunJob'
        and resource.type = 'cloud_run_job'
),

load_requests as (
    select
        'function' as run_type,
        resource.labels.service_name as pipeline,
        insertId as run_id,
        timestamp as occurred_at,
        concat('HTTP ', cast(httpRequest.status as string)) as detail,
        httpRequest.status < 400 as is_success
    from {{ source('bronze', 'run_googleapis_com_requests') }}
    where resource.labels.service_name = 'pbk-ingest-load'
)

select
    *,
    if(is_success, 'success', 'failure') as status
from job_executions
union all
select
    *,
    if(is_success, 'success', 'failure') as status
from load_requests
