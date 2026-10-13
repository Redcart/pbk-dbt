{% macro hash_key(columns) -%}
    to_hex(md5(concat({%- for c in columns %}coalesce(cast({{ c }} as string), ''){{ ", '|', " if not loop.last }}{%- endfor %})))
{%- endmacro %}

{% macro hashdiff(columns) -%}
    to_hex(md5(to_json_string(struct({{ columns | join(', ') }}))))
{%- endmacro %}

{# Rows to (re)process on an incremental run: everything ingested since the last row of this table
   (>= so the last processed snapshot is replayed for change detection), pruned on observed_at (target_col is its name in this table). #}
{% macro vault_window(target_col='observed_at') -%}
    {%- if is_incremental() -%}
        ingested_at >= (select max(ingested_at) from {{ this }})
        and observed_at >= (select timestamp_sub(max({{ target_col }}), interval 1 day) from {{ this }})
    {%- else -%}
        true
    {%- endif -%}
{%- endmacro %}
