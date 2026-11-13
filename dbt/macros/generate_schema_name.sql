{#
    Where a model lands depends on who runs it.

    runtime target   the configured schema as is: STAGING, MARTS.
    any other target the target schema as a prefix: DBT_ANNA_MARTS, PR_42_MARTS.

    People and pull requests therefore never write into the schemas the scheduled job owns.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'runtime' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- elif custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ target.schema | trim }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
