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

{# One station per bike and snapshot. The API can list a bike at several stations in the same snapshot (always 2 so far,
   about once every 700 snapshots on dev): the bike stays where it was last seen, ties (new bike, or no listed station is
   the previous one) go to the lowest station_id.
   `relation` is a CTE with snapshot_id, station_id, bike_id and observed_at, already cut with vault_window: the window
   functions below cannot sit in a view, they would run on the whole history and read every payload. #}
{% macro one_station_per_bike(relation) -%}
    select * except (previous_pair_at, previous_seen_at)
    from (
        select
            *,
            lag(observed_at) over (partition by bike_id, station_id order by observed_at) as previous_pair_at,
            timestamp_micros(max(unix_micros(observed_at)) over (
                partition by bike_id order by unix_micros(observed_at) range between unbounded preceding and 1 preceding
            )) as previous_seen_at
        from {{ relation }}
    )
    qualify row_number() over (
        partition by bike_id, snapshot_id
        order by coalesce(previous_pair_at = previous_seen_at, false) desc, station_id
    ) = 1
{%- endmacro %}
