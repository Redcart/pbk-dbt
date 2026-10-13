# pbk-dbt

dbt project transforming PubliBike data in BigQuery: bronze (`bronze.publibike_snapshots`, loaded by pbk-ingest) → silver (staging views, Data Vault 2.0) → gold (dims, facts). See `dbt.md` for the design.

```bash
make install                      # uv sync --dev
source .envrc                     # GCP_PROJECT_ID (see .envrc.example)
uv run dbt build --profiles-dir . # run models + tests against the project in GCP_PROJECT_ID
uv run dbt source freshness --profiles-dir .
```

Python 3.14, dbt-core 1.12, dbt-bigquery 1.12. See `dbt.md` for the design, status and CI/CD; `archive/` holds the previous implementation (reference only).
