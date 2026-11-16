{#
    Remove what a pull request built: the schema PR_<number> and every PR_<number>_* schema.

        dbt run-operation drop_pr_schemas --args '{pr_number: 42}' --target ci

    Only runs on the ci target and only for a plain number, so it cannot be pointed at the
    schemas the scheduled job owns.
#}
{% macro drop_pr_schemas(pr_number) %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error('drop_pr_schemas only runs on the ci target.') }}
    {% endif %}
    {% if not modules.re.match('^[0-9]+$', pr_number | string) %}
        {{ exceptions.raise_compiler_error('pr_number must be a number, got: ' ~ pr_number) }}
    {% endif %}

    {% set prefix = 'PR_' ~ pr_number %}
    {% set found %}
        select schema_name
        from {{ target.database }}.information_schema.schemata
        where schema_name = '{{ prefix }}'
           or startswith(schema_name, '{{ prefix }}_')
    {% endset %}

    {% for row in run_query(found).rows %}
        {% do log('Dropping ' ~ target.database ~ '.' ~ row[0], info=True) %}
        {% do run_query('drop schema if exists ' ~ target.database ~ '."' ~ row[0] ~ '" cascade') %}
    {% endfor %}
{% endmacro %}
