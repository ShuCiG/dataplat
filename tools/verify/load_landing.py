"""Create the landing tables of an environment and load daily partitions into them by hand.

This is the manual twin of what the orchestrator does on every run. Use it to seed a fresh
environment or to repeat a load while debugging. It is idempotent: Snowflake remembers which
files a table has loaded, so a second run of the same partitions loads 0 rows.

    SNOWFLAKE_ORGANIZATION_NAME=... SNOWFLAKE_ACCOUNT_NAME=... SNOWFLAKE_USER=... \\
    python load_landing.py dev 2025-03-15 3
"""

from __future__ import annotations

import os
import sys
from datetime import date, timedelta
from pathlib import Path

import pyarrow as pa

from datagen.schemas import SCHEMAS

DDL_DIR = Path(__file__).resolve().parents[2] / "airflow" / "dags" / "sql" / "ddl"


def select_list(schema: pa.Schema) -> str:
    """Pick every file column out of the Parquet row, casting timestamps explicitly."""
    parts = []
    for field in schema:
        ref = f"$1:{field.name}"
        parts.append(f"{ref}::timestamp_tz" if pa.types.is_timestamp(field.type) else ref)
    return ", ".join(parts)


def copy_sql(entity: str, day: date) -> str:
    columns = ", ".join([f.name for f in SCHEMAS[entity]] + ["_source_file", "_file_row_number"])
    return (
        f"copy into {entity} ({columns}) from ("
        f"select {select_list(SCHEMAS[entity])}, metadata$filename, metadata$file_row_number "
        f"from @s3_landing/{entity}/load_date={day.isoformat()}/) "
        "file_format = (format_name = parquet)"
    )


def connect(env: str):
    import snowflake.connector

    return snowflake.connector.connect(
        account=f"{os.environ['SNOWFLAKE_ORGANIZATION_NAME']}-{os.environ['SNOWFLAKE_ACCOUNT_NAME']}",
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider=os.environ.get("SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER", "OIDC"),
        token=os.environ.get("SNOWFLAKE_TOKEN"),
        role=os.environ.get("SNOWFLAKE_ROLE", "PLATFORM_ADMIN"),
        warehouse=f"{env}_LOADING_WH",
        database=f"{env}_RAW",
        schema="LANDING",
    )


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: load_landing.py <env> <first-date YYYY-MM-DD> <days>", file=sys.stderr)
        return 2
    env, first, days = argv[1].upper(), date.fromisoformat(argv[2]), int(argv[3])
    con = connect(env)
    try:
        cur = con.cursor()
        for entity in SCHEMAS:
            cur.execute((DDL_DIR / f"{entity}.sql").read_text(encoding="utf-8"))
        for offset in range(days):
            day = first + timedelta(days=offset)
            for entity in SCHEMAS:
                cur.execute(copy_sql(entity, day))
                rows = cur.fetchall()
                loaded = sum(r[3] for r in rows if r[1] == "LOADED") if rows and len(rows[0]) > 3 else 0
                print(f"{day} {entity:12} loaded {loaded} rows")
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
