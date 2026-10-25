-- One row per bronze snapshot: how late it landed and how long since the previous one.
-- Snapshots are expected every `snapshot_interval_minutes`; a larger gap means missed snapshots.
with snapshots as (
    select
        snapshot_id,
        observed_at,
        ingested_at,
        timestamp_diff(observed_at, lag(observed_at) over (order by observed_at), minute) as minutes_since_previous_snapshot
    from {{ ref('stg_snapshots') }}
)

select
    snapshot_id,
    observed_at,
    ingested_at,
    timestamp_diff(ingested_at, observed_at, second) as ingestion_lag_seconds,
    minutes_since_previous_snapshot,
    greatest(round(minutes_since_previous_snapshot / {{ var('snapshot_interval_minutes') }}) - 1, 0) as missed_snapshots
from snapshots
