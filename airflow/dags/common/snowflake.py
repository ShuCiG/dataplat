"""Snowflake access for the loading tasks.

The session signs in with the AWS role of the task (workload identity), so there is no password
or key anywhere. The user is <ENV>_AIRFLOW_SVC and it is bound to the <ENV>_LOADER role.
"""

from __future__ import annotations

import os

from common.config import environment


def connect():
    import snowflake.connector

    env = environment().upper()
    return snowflake.connector.connect(
        account=f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}",
        user=f"{env}_AIRFLOW_SVC",
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider="AWS",
        role=f"{env}_LOADER",
        warehouse=f"{env}_LOADING_WH",
        database=f"{env}_RAW",
        schema="LANDING",
    )


def copy_into_sql(entity: str, load_date: str) -> str:
    """Load one daily partition of one entity.

    Columns are matched by name, so the statement needs no column list. Snowflake remembers
    which files a table has loaded: repeating this for the same partition loads 0 rows.
    """
    return (
        f"copy into {entity} "
        f"from @s3_landing/{entity}/load_date={load_date}/ "
        "file_format = (format_name = parquet) "
        "match_by_column_name = case_insensitive "
        "include_metadata = ("
        "_source_file = metadata$filename, "
        "_file_row_number = metadata$file_row_number, "
        "_loaded_at = metadata$start_scan_time)"
    )
