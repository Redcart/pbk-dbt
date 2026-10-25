{% macro hash_key(columns) -%}
    to_hex(md5(concat({%- for c in columns %}coalesce(cast({{ c }} as string), ''){{ ", '|', " if not loop.last }}{%- endfor %})))
{%- endmacro %}

{% macro hashdiff(columns) -%}
    to_hex(md5(to_json_string(struct({{ columns | join(', ') }}))))
{%- endmacro %}

{# Rows to (re)process in this run.
   Every model of a run reads the same slice of bronze: rows ingested up to `run_started_at` minus a margin. Without the
   cutoff, models running in parallel see different snapshots (bronze keeps receiving rows), so a satellite could
   reference a link row another model has not read yet and the relationships tests fail until the next run.
   Incremental: everything ingested since the last row of this table (>= so the last processed snapshot is replayed,
   which closed detection needs), pruned on observed_at (target_col is its name in this table). #}
{% macro vault_window(target_col='observed_at') -%}
    ingested_at <= timestamp('{{ (run_started_at - modules.datetime.timedelta(minutes=2)).strftime("%Y-%m-%d %H:%M:%S") }}')
    {%- if is_incremental() %}
        and ingested_at >= (select max(ingested_at) from {{ this }})
        and observed_at >= (select timestamp_sub(max({{ target_col }}), interval 1 day) from {{ this }})
    {%- endif -%}
{%- endmacro %}
