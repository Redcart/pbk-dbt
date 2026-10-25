-- One row per request received by the monitored Cloud Run Functions (var `cloud_run_functions`, e.g. the
-- `pbk-ingest-load` load function triggered by Pub/Sub).
select
    resource.labels.service_name as function_name,
    insertId as log_id,
    timestamp as occurred_at,
    httpRequest.status as http_status,
    httpRequest.status < 400 as is_success
from {{ source('bronze', 'run_googleapis_com_requests') }}
where resource.labels.service_name in unnest({{ var('cloud_run_functions') }})
