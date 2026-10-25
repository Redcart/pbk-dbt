# pbk-dbt — Data Transformation (Medallion + Data Vault 2.0)

**Purpose:** dbt project that transforms raw PubliBike data in BigQuery through a medallion architecture (silver, gold) using Data Vault 2.0 modeling for the silver layer.

---

## Implementation Status (dev)

| Area | State |
|---|---|
| Bronze → silver staging | Done: `stg_snapshots`, `stg_stations`, `stg_station_bikes` (views in `silver`), source freshness on `bronze.publibike_snapshots` |
| Data Vault | Done: `hub_stations`, `hub_bikes`, `lnk_station_bike`, `sat_stations`, `sat_bikes`, `sat_station_bike_eff`, all incremental, with tests |
| Gold | Done: `dim_stations`, `dim_bikes`, `fct_station_capacity` and `fct_trips` (tables in `gold`) |
| Runner | `runner.py` + `data_product.yml` (jobs `refresh`, `full_refresh`), Docker image |
| CI/CD | GitHub Actions: PR checks, CD (dev/stg), release (prd), manual full refresh |
| Monitoring | Done: `mon_ingestion_freshness`, `mon_pipeline_runs`, `mon_dbt_runs` (log sink tables in `bronze` confirmed in dev) |
| ML, Lightdash | Not started |

`archive/` holds the previous implementation (Cloud Function style, SQL run from Python); it is excluded from lint and pre-commit and kept for reference only.

---

## Local Development

The dbt project sits at the repository root (`dbt_project.yml`, `profiles.yml`, `models/`, `macros/`).

```bash
make install                              # uv sync --dev
source .envrc                             # see .envrc.example
uv run dbt build --profiles-dir .
uv run dbt source freshness --profiles-dir .
make dbt-parse                            # static check, no BigQuery (what CI runs)
```

- **`GCP_PROJECT_ID`** — the project of the target environment (`pbk-dev-bda8` for dev); the only thing that changes between targets, since dataset names are the same everywhere.
- **`DBT_IMPERSONATE_SERVICE_ACCOUNT`** — dev only: `pbk-dbt@<project>.iam.gserviceaccount.com`. The daily user cannot run BigQuery jobs, so dbt acts as the runtime SA (`impersonate_service_account` in `profiles.yml`, no key; needs `serviceAccountTokenCreator`, see `dev-environment.md`). Unset in Cloud Run, where the runtime SA is the identity.
- **Python 3.14** — `mashumaro` is pinned `>=3.17` in `pyproject.toml`: the 3.14 release dbt resolves by default fails on import under Python 3.14. Drop the pin once dbt-common requires a newer version.
- **Auth method** — `oauth` (Application Default Credentials) for every target; the three targets (`dev`, `stg`, `prd`) are identical.

---

## What This Repository Is NOT

- Infrastructure provisioning (Terraform) — handled by pbk-infra
- Data ingestion — handled by pbk-ingest (owns the bronze layer)
- ML forecasting — handled by pbk-ml
- BI dashboarding — handled by pbk-dash

---

## Architecture

This repository is a dbt project using BigQuery as the data warehouse. Raw data sources live in BigQuery tables (JSON payload), loaded by pbk-ingest. All three layers (bronze, silver, gold) live in the same GCP project (one project per environment: dev, stg, prd).

**Layer ownership:**
- **Bronze** — owned by pbk-ingest (dbt source only, not modeled here)
- **Silver & Gold** — owned by this repository

### BigQuery datasets

One dataset per layer, **same names in every environment** (the GCP project is what changes):

| Dataset | Layer | Written by | Contents |
|---|---|---|---|
| `bronze` | Bronze | pbk-ingest | `publibike_snapshots` (raw JSON payload) |
| `silver` | Silver | pbk-dbt | `stg_*` views, hubs, links, satellites |
| `gold` | Gold | pbk-dbt (and BQML outputs) | dims, facts, ML features and forecasts |

The datasets are created by pbk-infra in the `EU` multi-region (see *Locations* in `infra.md`), so the dbt profile sets `location: EU`; dbt only creates tables and views inside them. By default dbt would prefix a custom schema with the profile's dataset (`<profile dataset>_gold`), so the project overrides `generate_schema_name` to use the name as-is:

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
```

```yaml
# dbt_project.yml
models:
  pbk:
    staging: { +schema: silver }
    vault:   { +schema: silver }
    marts:   { +schema: gold, +materialized: table }
    ml:      { +schema: gold, +materialized: table }
    monitoring: { +schema: gold, +materialized: table }
```

**No views in `gold`** — Lightdash can only read `gold` (dataset-level IAM, see `dashboard.md`), and a view on `silver` would need `silver` access. Gold models are tables by default; incremental models override it per model.

### One rule: dbt builds everything that is read

Other components only **land raw inputs in `bronze`**; dbt is the only thing that builds `silver` and `gold`, and dashboards read **`gold` only**.

```
Producers (write to bronze only)          dbt                                   Consumers
─────────────────────────────────         ───────────────────────────────       ─────────
pbk-ingest → publibike_snapshots   ┐
Cloud Logging sink → log tables    ├──→   stg_* (silver) → gold models   ──→    Lightdash, pbk-ml
pbk-ml     → forecasts, ml_model_runs ┘
```

### Sources (`bronze`)

| Source | Written by | Used for |
|---|---|---|
| `publibike_snapshots` | pbk-ingest (Cloud Function) | business models (vault, dims, facts), ingestion monitoring |
| Log sink tables (e.g. `run_googleapis_com_stderr`) | Cloud Logging sink (pbk-infra) | pipeline and dbt run monitoring |
| `forecasts`, `ml_model_runs` | pbk-ml (phase 2) | forecasts, forecast accuracy, model metrics |

- **Log table names** are generated by Cloud Logging from the log name. Confirmed on dev: `run_googleapis_com_stdout`, `run_googleapis_com_stderr`, `run_googleapis_com_requests`, `run_googleapis_com_varlog_system`, `cloudaudit_googleapis_com_system_event`; the ones used are declared in `_sources.yml`. A table only exists after its first log entry, so a fresh environment (stg, prd) needs the sink and one pipeline run before the `monitoring` models can build.
- **The sink delivers some entries more than once** (same `insertId`, same timestamp): models dedupe on `insertId`.
- **dbt logs in JSON** — the runner calls dbt with `--log-format json`, so each model/test result is one structured log line, easy to parse from the sink.
- **Source freshness** — `dbt source freshness` runs on every source, so a stopped producer shows up as a failed check.

---

## dbt Runner (Cloud Run Job)

**dbt Core only — no dbt Cloud.** Orchestration is Cloud Scheduler + Cloud Run Job + `data_product.yml`; everything runs in our GCP projects.

The dbt project is packaged as a Docker image, pushed to Artifact Registry via GitHub Actions, and run as a Cloud Run Job.

**Python 3.14** (platform standard) with **dbt-core 1.12** (`>=1.12,<1.13`) and dbt-bigquery 1.12. Validated on 3.14 (dbt runs, tests pass); the only fix needed is the `mashumaro` pin described in *Local Development*.

Orchestration works via Cloud Scheduler: **one scheduler per scheduled job** (each job has its own cron, and a scheduler has only one), all triggering the same Cloud Run Job `pbk-dbt`. `data_product.yml` declares the runs the image can perform, so a single image serves every schedule.

```yaml
# data_product.yml
name: publibike
jobs:
  - name: refresh             # every 5 minutes: vault + marts in DAG order
    schedule: "*/5 * * * *"
    command: build
    args: ["--select", "vault", "marts"]
  - name: full_refresh        # manual only
    schedule: null
    command: build
    args: ["--full-refresh"]
```

- **`runner.py`** is the image entry point (`ENTRYPOINT ["python", "runner.py"]`). The container args are the job name plus optional extra dbt args: `python runner.py <job> [extra args]` runs `dbt --log-format json <command> <args> <extra args>`, and returns dbt's exit code, so a failed model or test fails the Cloud Run execution. `python runner.py schedules` prints `<job>\t<cron>` for every scheduled job (used by the deploy workflow).
- **Scheduler → job** — each scheduler POSTs to the Cloud Run `jobs/pbk-dbt:run` API with the body `{"overrides":{"containerOverrides":[{"args":["<job>"]}]}}`, authenticated as the runtime SA. Scheduler names are `pbk-dbt-<job>` (underscores replaced by hyphens). With several data products the names must include the product (`pbk-dbt-<product>-<job>`) and the runner must take a product: not needed while there is a single `data_product.yml`.
- **Image** — `python:3.14-slim` + pinned uv, dependencies from `uv.lock`, then the dbt project and `runner.py`. Configuration comes from the `GCP_PROJECT_ID` environment variable only.
- **Cloud Run Job settings** — 1 GiB, 1 CPU, 600 s task timeout, no retries (the next 5-minute run is the retry).

### CI/CD (GitHub Actions)

| Workflow | Trigger | What it does |
|---|---|---|
| `pull_request_checks.yml` | PR to `dev`/`stg`/`prd` | CI |
| `cd.yml` | push to `dev`, `stg` | CI → image → deploy |
| `release.yml` | tag `v*.*.*` | CI → image check + version tag → deploy to `prd` |
| `full_refresh.yml` | manual | executes the Cloud Run Job with `full_refresh` |
| `reusable_wf.yml` | called | CI: pre-commit, pytest, `dbt parse` (no GCP credentials) |
| `deploy_wf.yml` | called | `image` → (`deploy-job` ‖ `deploy-schedulers`) |

```
ci ──► image ──┬──► deploy-job          (gcloud run jobs deploy)
               └──► deploy-schedulers   (create/update one scheduler per scheduled job)
```

- **`image`** — `dev` builds and pushes `<GAR>/pbk-dbt/pbk-dbt:<sha>`; `stg`/`prd` only check that the image of the same SHA exists (never rebuild); a release also adds the version tag.
- **`dbt parse`** — catches Jinja/YAML errors, broken `ref`/`source`, config typos without BigQuery. It does not run the SQL: column or JSON-path mistakes only surface in `dbt build` on dev.
- **Permissions needed** (provisioned by pbk-infra): `pbk-dbt-gh` — Artifact Registry writer on the `pbk-dbt` repository, `roles/run.developer`, `roles/iam.serviceAccountUser` on the runtime SA, `roles/cloudscheduler.admin`; runtime SA `pbk-dbt` — `roles/run.developer` on the job (so schedulers can start it with an args override), BigQuery job user on the project, viewer on `bronze`, editor on `silver` and `gold`.

---

## Lightdash Semantic Layer

pbk-dbt owns what can be explored in Lightdash: the gold models and their dimensions/metrics, declared in the model YAML (`config.meta`). pbk-dash owns the server and the charts built on top (see *Who Pushes What to Lightdash* in `dashboard.md`).

```yaml
# models/marts/_marts.yml
models:
  - name: fct_station_capacity
    columns:
      - name: bikes_available
        config:
          meta:
            metrics:
              avg_bikes_available: { type: average }
```

**In CD** (dev, stg, and the prd release), after the runner image is deployed and new/changed models are built in BigQuery (Lightdash reads column types from the warehouse):

```yaml
- run: npx @lightdash/cli deploy
  env:
    LIGHTDASH_URL: ${{ vars.LIGHTDASH_URL }}
    LIGHTDASH_PROJECT: ${{ vars.LIGHTDASH_PROJECT_UUID }}
    LIGHTDASH_API_KEY: ...                                   # Secret Manager lightdash-api-key
    LIGHTDASH_PROXY_AUTHORIZATION: Bearer ${{ steps.iap.outputs.id_token }}   # IAP, same as pbk-dash
```

- **`lightdash deploy` compiles the dbt project** — the CI/CD SA needs BigQuery read on `gold` for that step.
- **First time per environment:** `lightdash deploy --create` creates the Lightdash project and its BigQuery connection (manual, see `dashboard.md`).

---

## Medallion & Data Vault 2.0

### Staging (silver)

Before modeling Data Vault entities, `stg_` dbt models (BigQuery Views) extract the fields we need from the raw JSON payload. All downstream silver/gold models read from staging, never from the raw bronze table directly. See `raw_data.txt` for the expected raw format.

### Data Vault 2.0 entities

Modeling PubliBike (velospot) data:
- **Hubs:** stations, bikes
- **Links:** station-bike
- **Satellites:** station details over time, station-bike relationships over time

All entities are materialized as tables. Hubs need no partitioning nor clustering. Satellites are partitioned by time (and likely clustered).

**Station example:** `hub_stations` records every station that has ever existed. `sat_stations` captures descriptive, time-varying details (max capacity, address) and station status (`active`/`closed`) — a station missing from the feed is marked `closed`; if it reappears (e.g. after maintenance), it's marked `active` again. This drives `dim_stations` in gold: the current network of active stations.

**As implemented:**
- **Keys** — hash key = `md5` of the business key(s) joined by `|` (`hash_key` macro); `hashdiff` = `md5` of the JSON of the descriptive columns plus `status` (`hashdiff` macro).
- **Hubs and link** — incremental `merge` on the hash key (BigQuery has no `append` strategy); only keys not yet in the table are selected, so the merge only inserts. Columns: hash key(s), business key(s), `first_seen_at`, `ingested_at`, `record_source`.
- **`sat_stations`** — descriptive attributes (number, name, address, latitude, longitude, details route) and `status`. Bike counts change every snapshot and belong to `fct_station_capacity`, not to this satellite.
- **`sat_bikes`** — `bike_range` over time. No status: a bike absent from the feed is simply rented, not closed.
- **`sat_station_bike_eff`** — effectivity of the link: `active` when a bike shows up at a station, `closed` when it is gone from that station in the next snapshot. Basis for `fct_trips`.
- **Closed detection** — a station (or station-bike pair) present in a snapshot but absent from the next one gets a `closed` row stamped with the next snapshot's time; a reappearance is a new `active` row. Snapshot order comes from `stg_snapshots`, which reads only the metadata columns, never the payload.

**Station feed → satellite insert logic:**
```
                 STATION FEED
                      │
          ┌───────────┴───────────┐
          │                       │
   station already known     station never seen
          │                       │
     compare state             new hub
          │                       │
    ┌─────┴─────┐                 │
    │           │                 │
 changed     unchanged             │
    │           │                 │
 INSERT       NOTHING            INSERT
 SAT          into SAT            SAT
```

### Gold as implemented

- **`dim_stations`** — latest `sat_stations` row per station, only `active` (the current network).
- **`dim_bikes`** — every bike ever seen with its latest `bike_range`, `current_station_id` (null while rented) and `is_available`, from the latest `sat_station_bike_eff` rows.
- **`fct_station_capacity`** — one row per station and snapshot: `bikes_available`, `electric_bikes_available`, `standard_bikes_available`. Incremental `merge` on `station_snapshot_hk`, partitioned on `observed_at`, clustered by `station_id`, same `vault_window` watermark as the satellites. Reads `stg_stations` directly (no vault dependency). Carries the Lightdash metrics (`avg_bikes_available`, `avg_electric_bikes_available`).
- **`fct_trips`** — one row per completed trip: a bike's `closed` event at a station followed by its next `active` event at a station (`start_station_id`, `end_station_id`, `started_at`, `ended_at`, `duration_minutes`). Incremental `merge` on `trip_hk` (bike + departure time), partitioned on `started_at`, clustered by `start_station_id`, `bike_id`.
  - **Accuracy** — times are snapshot times, so a trip is accurate to one snapshot (5 minutes). `started_at` is the first snapshot without the bike, `ended_at` the first one with it again; a bike that moves between two stations within one interval gets a 0-minute trip.
  - **Not yet returned** — a bike still out is not a trip yet; it appears once it shows up at a station.
  - **Lookback** — an incremental run looks back 7 days from the latest `ended_at` for the departure of a returning bike; a longer rental is only picked up by `full_refresh`.
  - **Noise** — on dev (about 2 days): 31k trips, median duration 5 minutes, 9% at 0 minutes, 5% start and end at the same station. Short trips include bikes that briefly drop out of the feed; filtering them (for example `duration_minutes >= 5`) is a dashboard choice, not applied in the model.
- **Lightdash metrics** are declared under `config.meta` (the top-level `meta` on columns is deprecated in dbt 1.12).
- **`mon_ingestion_freshness`** (`models/monitoring`, table in `gold`) — one row per bronze snapshot: `ingestion_lag_seconds` (`ingested_at - observed_at`), `minutes_since_previous_snapshot` and `missed_snapshots` (gap / `snapshot_interval_minutes` - 1; the var is 5 and must follow the extract schedule in pbk-ingest). Built from `stg_snapshots`, so it never reads the JSON payload. Metrics: average and max lag, max gap, total missed snapshots. On dev: 288 snapshots a day, average lag about 26 s; the first day shows the gaps from before ingestion was stable.
- **Staging for the log sink** — the `mon_*` models read three `stg_*` views, not the sink tables: `stg_dbt_log_events` (flattens dbt's JSON logs in `run_googleapis_com_stdout`, `jsonPayload.info.name` = `LogModelResult` / `LogTestResult`, strips colour codes), `stg_cloud_run_job_events` (job execution results from `system_event`), `stg_cloud_run_function_events` (load function requests). The monitored names are dbt vars in `dbt_project.yml` (`cloud_run_functions`, a list, and `dbt_job_name`), so renaming or adding a function is a one-line change. Dedupe on `insertId` is done in `mon_dbt_runs`, after its time filter, so the filter still prunes partitions.
- **`mon_dbt_runs`** — one row per model or test result of every dbt run: `execution_name`, `invocation_id`, `node_type`, `node_name`, `status`, `is_failure`, `execution_time_seconds`, `message` (colors stripped). Incremental `merge` on the log `insertId` with a 1-hour lookback for late entries. Metrics: failed nodes, average node time.
- **`mon_pipeline_runs`** — one row per Cloud Run job execution (`pbk-ingest-extract`, `pbk-dbt`) and per `pbk-ingest-load` request (success when HTTP < 400). In `stg_cloud_run_job_events`, only `completed successfully` and `failed to complete` events count: Cloud Run also logs `has been deleted` when it cleans up old executions, which is not a run result (it was inflating failures with thousands of false rows).
- **Scheduling** — the single `refresh` job builds `vault`, `marts` and `monitoring` together so dbt orders them by dependency; separate jobs would race on silver.

### Layer overview

This may evolve as modeling progresses, but the current plan:

- **Bronze (dbt source):** `bronze.publibike_snapshots`
- **Silver:**
  - `stg_*` (BigQuery Views)
  - `hub_stations`, `hub_bikes` (BigQuery Tables)
  - `lnk_station_bike` (BigQuery Table)
  - `sat_stations`, `sat_bikes`, `sat_station_bike_eff` (BigQuery Tables, partitioned and clustered)
- **Gold:**
  - `dim_stations`, `dim_bikes` — current active network (BigQuery Tables)
  - `fct_station_capacity` — bikes available per station and snapshot (incremental; feeds dashboards and forecasting)
  - `fct_trips`
  - **ML:** `fct_forecasts` (phase 1: BigQuery ML in this repo; phase 2: from `bronze.forecasts`), `fct_forecast_accuracy` (forecasts vs. `fct_station_capacity`), `fct_model_runs` (one row per training, from `bronze.ml_model_runs`)
  - **Monitoring:** `mon_ingestion_freshness` (from `bronze.publibike_snapshots`), `mon_pipeline_runs` (extract job and load function executions, from the log sink), `mon_dbt_runs` (dbt model/test results, from dbt's JSON logs in the sink)

Monitoring and ML inputs only need `stg_*` views in `silver` — hubs, links and satellites are for business entities (stations, bikes).

Gold layer tables are consumed by:
- BI dashboarding (pbk-dash)
- ML forecasting data prep for station capacity (pbk-ml) — feature tables still live in this repo's gold layer

---

## Storage Optimization

Satellites and fact tables grow with every snapshot, so they use `incremental` materialization instead of full-refresh tables — each run appends/merges only new or changed rows rather than rebuilding the whole table.

**Per-table strategy:**

| Table | Materialization | Partition | Cluster by |
|---|---|---|---|
| `hub_stations`, `hub_bikes`, `lnk_station_bike` | incremental (insert-only merge) | — | — |
| `sat_stations` | incremental | `DATE(observed_at)` | `station_hk` |
| `sat_bikes` | incremental | `DATE(observed_at)` | `bike_hk` |
| `sat_station_bike_eff` | incremental | `DATE(observed_at)` | `station_hk` |
| `fct_station_capacity` | incremental | `DATE(observed_at)` | `station_hk` |
| `fct_trips` | incremental | `DATE(started_at)` | `station_id`, `bike_id` |

**Why:**
- **Partition by day** — most queries (dashboards, monitoring, forecasting) filter on a recent time window; day partitioning lets BigQuery prune old partitions and keeps scan cost/time down.
- **Cluster by `station_id`/`bike_id`** — hub-level lookups and joins filter or group by these keys constantly (per-station capacity, per-bike history), so clustering colocates matching rows within each partition.
- **Hubs stay full tables** — they're small, append-only, and rarely filtered by time, so partitioning/clustering adds overhead without a query-time benefit (consistent with "Hubs need no partitioning nor clustering" above).

---

## Full Refresh (Rebuild From Bronze)

Silver and gold are **derived and disposable**: at any time, the whole thing can be rebuilt from bronze with one command. Typical trigger: we start using a raw field that was ignored so far (e.g. `ebikes_available` in `sat_stations`) and want it filled across the full history, not just from today on.

### Prerequisites

- **Bronze keeps full history** — no partition expiration on `publibike_snapshots`. Bronze is the source of truth; silver/gold are rebuildable caches.
- **Bronze keeps every field the API returns** — a field can only be "leveraged later" if it was stored in the first place. Staging picks fields; bronze never drops them.
- **Incremental models are replayable** — the same SQL must give the same result whether it runs on 5 minutes of data or on the full history (see below).

### Replayable incremental models

The satellite change detection (see *Station feed → satellite insert logic*) runs **within the batch** (`LAG` over the staged rows) and, on incremental runs only, also against the latest row already in the table. On full refresh there is no previous row, so the whole history is replayed through the same logic:

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['station_hk', 'loaded_at'],
    on_schema_change='fail',
    partition_by={'field': 'loaded_at', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['station_id'],
) }}

with src as (
    select * from {{ ref('stg_stations') }}
    {% if is_incremental() %}
    where loaded_at > (select max(loaded_at) from {{ this }})
    {% endif %}
),

changes as (
    select *, lag(hashdiff) over (partition by station_hk order by loaded_at) as prev_hashdiff
    from src
)

{% if is_incremental() %}
, latest as (
    select station_hk, hashdiff as last_hashdiff
    from {{ this }}
    qualify row_number() over (partition by station_hk order by loaded_at desc) = 1
)
{% endif %}

select changes.* except (prev_hashdiff)
from changes
{% if is_incremental() %}
left join latest using (station_hk)
{% endif %}
where hashdiff is distinct from coalesce(prev_hashdiff{% if is_incremental() %}, last_hashdiff{% endif %})
```

- **Watermark-based** (`max(loaded_at)` from the target) — no run state stored anywhere else, so a rebuilt table is immediately a valid starting point for the next scheduled run.
- **`on_schema_change='fail'`** — adding a column to a satellite changes its `hashdiff` and would leave history `NULL` with `append_new_columns`. Failing forces the explicit decision: run a full refresh.

> **Decision — time columns.** Satellites keep both bronze timestamps, each with one job:
> - **`ingested_at` → incremental watermark.** With `observed_at`, a late snapshot is lost: 12:30 is delayed by a Pub/Sub retry and loads after 12:35, the watermark is already 12:35, so 12:30 is skipped forever. `ingested_at` only moves forward.
> - **`observed_at` → change-detection ordering and partitioning.** A change is defined by the order snapshots were taken, not loaded; dashboards and forecasting filter on business time, so partition pruning uses it.
>
> **As implemented** (`vault_window` macro): an incremental run reads staging rows with `ingested_at >= max(ingested_at)` of the table (`>=`, so the last processed snapshot is replayed, which closed detection needs), pruned with `observed_at >= max(observed_at) - 1 day`. The replayed rows are dropped by the hashdiff comparison against the latest row, so reruns are idempotent. The tables are partitioned on `observed_at`, not `loaded_at`; the unique key is `(hash key, observed_at)`.
>
> **Run cutoff.** The window is also capped at `ingested_at <= run_started_at - 2 minutes`, the same for every model of an invocation. Models run in parallel and bronze keeps receiving snapshots, so without the cap a satellite could read a snapshot its link had not seen, and the `relationships` tests failed transiently (about 15% of runs on dev, found with `mon_dbt_runs`). The 2-minute margin covers the delay between a row's `ingested_at` and its visibility in BigQuery; rows past the cutoff are picked up by the next run.
>
> **Trade-offs accepted:**
> - A late snapshot is compared against the latest satellite row, not its true predecessor in time, which can create or miss a change. Late loads should be rare, and a full refresh replays everything in `observed_at` order and corrects it.
> - The watermark is the last row *written* (a satellite only gets rows on change), so a run reprocesses everything ingested since the last change of any station. Cheap today (second run on dev: 0 rows merged, about 2 MiB scanned); revisit with a snapshot ledger if it grows.

### How to run it

`data_product.yml` declares a `full_refresh` job with **no schedule** — manual only, same image, same Cloud Run Job:

```yaml
  - name: full_refresh
    type: dbt_run
    schedule: null
    command: build
    args:
      - "--full-refresh"
```

`dbt build` rebuilds every model and runs tests in DAG order. Data volume is small (~250 stations × 288 snapshots/day), so rebuilding everything is simpler than selecting a subset. When needed, narrow it with `--select stg_stations+`.

Triggered from a `workflow_dispatch` GitHub Actions workflow in pbk-dbt (input: environment), which executes the Cloud Run Job with the same override the schedulers send. PRD requires approval through the GitHub environment protection rule.

Implemented as `.github/workflows/full_refresh.yml` (below). The job name reaches the runner through `--args`, the same way the schedulers send it.

```yaml
# .github/workflows/full_refresh.yml
name: 'dbt full refresh'

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        type: choice
        options: [dev, stg, prd]
        required: true
      select:
        description: 'Optional dbt selector (e.g. stg_stations+). Empty = everything'
        type: string
        required: false
        default: ''

concurrency:
  group: full-refresh-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  full_refresh:
    environment: ${{ inputs.environment }}
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'

    env:
      GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
      GCP_PROJECT_NUMBER: ${{ vars.GCP_PROJECT_NUMBER }}
      GCP_REGION: ${{ vars.GCP_REGION }}
      SERVICE_ACCOUNT_GH: ${{ vars.SERVICE_ACCOUNT_GH }}
      WIF_POOL_ID: ${{ vars.WIF_POOL_ID }}
      WIF_POOL_PROVIDER: ${{ vars.WIF_POOL_PROVIDER }}

    steps:
    - uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: 'projects/${{ env.GCP_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/${{ env.WIF_POOL_ID }}/providers/${{ env.WIF_POOL_PROVIDER }}'
        service_account: ${{ env.SERVICE_ACCOUNT_GH }}

    - uses: google-github-actions/setup-gcloud@v2

    - name: Execute Cloud Run Job
      env:
        SELECT: ${{ inputs.select }}
      run: |
        ARGS="full_refresh"
        if [ -n "$SELECT" ]; then
          ARGS="$ARGS,--select,$SELECT"
        fi

        gcloud run jobs execute pbk-dbt \
          --project="$GCP_PROJECT_ID" \
          --region="$GCP_REGION" \
          --args="$ARGS" \
          --wait
```

- **`environment: ${{ inputs.environment }}`** — resolves `vars` to the chosen environment. The `env:` block sits at job level because workflow-level `env` can't read environment-scoped variables.
- **PRD gate** — Settings → Environments → `prd` → Required reviewers.
- **`--args="full_refresh"`** — must match what the schedulers send. The runner reads the job name as its first argument, looks it up in `data_product.yml`, and appends any extra arguments (the optional `--select`). The override applies to this execution only.
- **`--wait`** — the workflow fails if the dbt build or its tests fail.
- **`concurrency`** — no two full refreshes at once in the same environment.
- **IAM** — `SERVICE_ACCOUNT_GH` needs `roles/run.developer` on the job (for `run.jobs.runWithOverrides`; `run.invoker` can't override args) and `roles/iam.serviceAccountUser` on the job's runtime service account.

CLI: `gh workflow run full_refresh.yml -f environment=dev -f select=stg_stations+`

**Workflow for a new field:**
1. Add the field to the `stg_` model and the satellite/mart (PR → dev).
2. Scheduled run fails on `on_schema_change='fail'` → run `full_refresh` in dev, check results.
3. Promote to stg → prd; run `full_refresh` in each environment after the deploy.
4. Retrain the BQML model if the field feeds the features.

**No need to pause schedulers:** BigQuery `CREATE OR REPLACE TABLE` swaps atomically, and the watermark logic makes the next 5-minute run pick up from wherever the rebuilt table ends.

---

## Repository Structure

```
dbt_project.yml  profiles.yml  data_product.yml  runner.py  Dockerfile
pyproject.toml  uv.lock  Makefile  .envrc.example
.github/workflows/        # pull_request_checks, cd, release, full_refresh, reusable_wf, deploy_wf
tests/                    # pytest for the runner
archive/                  # previous implementation, reference only

macros/
├── generate_schema_name.sql     # schema names used as-is (silver, gold)
└── vault.sql                    # hash_key, hashdiff, vault_window

models/
├── staging/                     # done
│   ├── _sources.yml             # bronze.publibike_snapshots (+ freshness)
│   ├── _staging.yml
│   ├── stg_snapshots.sql
│   ├── stg_stations.sql
│   ├── stg_station_bikes.sql
│   ├── stg_dbt_log_events.sql            # log sink: dbt results
│   ├── stg_cloud_run_job_events.sql      # log sink: job execution results
│   └── stg_cloud_run_function_events.sql # log sink: load function requests
├── vault/                       # done
│   ├── _vault.yml
│   ├── hub_stations.sql  hub_bikes.sql  lnk_station_bike.sql
│   └── sat_stations.sql  sat_bikes.sql  sat_station_bike_eff.sql
├── marts/                       # done
│   ├── _marts.yml               # tests + Lightdash metrics
│   ├── dim_stations.sql  dim_bikes.sql
│   ├── fct_station_capacity.sql
│   └── fct_trips.sql
├── ml/                          # planned
│   ├── station_capacity_features.sql
│   ├── fct_forecasts.sql  fct_forecast_accuracy.sql  fct_model_runs.sql
└── monitoring/                  # planned
    └── mon_ingestion_freshness.sql  mon_pipeline_runs.sql  mon_dbt_runs.sql

macros/ (planned)
├── train_station_capacity.sql
└── predict_station_capacity.sql
```
