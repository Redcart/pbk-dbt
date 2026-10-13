-- One row per snapshot, without reading the JSON payload.
select
    snapshot_id,
    observed_at,
    ingested_at
from {{ source('bronze', 'publibike_snapshots') }}
