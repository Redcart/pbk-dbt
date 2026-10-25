-- Result of every Cloud Run job execution (`pbk-ingest-extract`, `pbk-dbt`), from the audit log.
-- Cloud Run also logs "has been deleted" when it cleans up old executions: not a run result, left out.
select
    resource.labels.job_name as job_name,
    regexp_extract(protopayload_auditlog.status.message, r'Execution (\S+) ') as execution_name,
    timestamp as occurred_at,
    protopayload_auditlog.status.message as message,
    regexp_contains(protopayload_auditlog.status.message, r'completed successfully') as is_success
from {{ source('bronze', 'cloudaudit_googleapis_com_system_event') }}
where protopayload_auditlog.methodName = '/Jobs.RunJob'
    and regexp_contains(protopayload_auditlog.status.message, r'completed successfully|failed to complete')
