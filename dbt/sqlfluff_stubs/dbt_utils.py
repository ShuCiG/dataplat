"""Stand-ins for the dbt_utils macros, for sqlfluff only.

sqlfluff renders models with its own Jinja templater, which does not load dbt packages and, unlike
its dbt templater, needs no warehouse connection. These return SQL of the same shape as the real
macros, so the linter sees parseable code. Nothing here runs in dbt.
"""


def generate_surrogate_key(field_list):
    parts = " || '-' || ".join(f"coalesce(cast({field} as varchar), '_null_')" for field in field_list)
    return f"md5(cast({parts} as varchar))"


def date_spine(datepart, start_date, end_date):
    days = "table(generator(rowcount => 1000))"
    return f"select dateadd({datepart}, seq4(), {start_date}) as date_{datepart} from {days}"
