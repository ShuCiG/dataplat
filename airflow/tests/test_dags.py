"""Structure checks that need neither AWS nor Snowflake."""

import os
import sys
from itertools import pairwise
from pathlib import Path

import pytest

DAGS = Path(__file__).resolve().parents[1] / "dags"
sys.path.insert(0, str(DAGS))
os.environ.setdefault("PLATFORM_ENV", "dev")


@pytest.fixture(scope="module")
def dagbag():
    from airflow.dag_processing.dagbag import DagBag

    return DagBag(dag_folder=str(DAGS), bundle_path=DAGS, bundle_name="dags")


def test_dags_import_without_errors(dagbag):
    assert dagbag.import_errors == {}


def test_every_dag_has_owner_and_retries(dagbag):
    assert dagbag.dags
    for dag in dagbag.dags.values():
        assert dag.default_args["owner"], dag.dag_id
        assert dag.default_args["retries"] >= 1, dag.dag_id


def test_elt_daily_runs_in_the_documented_order(dagbag):
    dag = dagbag.dags["elt_daily"]
    order = [
        "platform_config",
        "check_partition",
        "create_raw_tables",
        "copy_into",
        "dbt_source_freshness",
        "dbt_build",
    ]
    for upstream, downstream in pairwise(order):
        assert downstream in dag.get_task(upstream).downstream_task_ids, (upstream, downstream)


def test_elt_daily_is_safe_to_rerun(dagbag):
    dag = dagbag.dags["elt_daily"]
    assert dag.max_active_runs == 1
    assert dag.catchup is False


def test_dag_files_name_no_resources():
    text = (DAGS / "elt_daily.py").read_text(encoding="utf-8")
    assert "arn:aws" not in text
    assert "dataplat-" not in text


def test_every_entity_has_ddl():
    from common import config

    assert config.entities() == ["customers", "order_items", "orders", "payments", "products"]


def test_copy_into_targets_the_partition_of_the_run():
    from common.snowflake import copy_into_sql

    sql = copy_into_sql("orders", "2025-03-15")
    assert "@s3_landing/orders/load_date=2025-03-15/" in sql
    assert "match_by_column_name" in sql


def test_rows_loaded_sums_loaded_files():
    from common.snowflake import rows_loaded

    result = [("a.parquet", "LOADED", 10, 10, 1, 0), ("b.parquet", "LOADED", 5, 5, 1, 0)]
    assert rows_loaded(result) == 15


def test_rows_loaded_is_zero_when_everything_was_loaded_before():
    from common.snowflake import rows_loaded

    assert rows_loaded([("Copy executed with 0 files processed.",)]) == 0
