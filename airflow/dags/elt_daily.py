"""Daily load of the landing zone into Snowflake, then dbt on ECS.

check_partition -> create_raw_tables -> copy_into (one per table) -> dbt_source_freshness -> dbt_build

The DAG is the same in every environment. PLATFORM_ENV picks the environment and the platform
configuration in SSM supplies every name. The partition to load is the logical date of the run,
so a backfill of any day loads that day.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.sdk import DAG, task
from common import config
from common.callbacks import notify_failure
from common.snowflake import connect, copy_into_sql


def cfg(key: str) -> str:
    """Template that reads one key of the platform configuration produced by platform_config."""
    return "{{ ti.xcom_pull(task_ids='platform_config')['" + key + "'] }}"


DEFAULT_ARGS = {
    "owner": "data-platform",
    "retries": 3,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=30),
    "on_failure_callback": notify_failure,
}


def dbt_task(task_id: str, command: list[str]) -> EcsRunTaskOperator:
    """Run one dbt command in the platform's task definition and stream its log into Airflow."""
    return EcsRunTaskOperator(
        task_id=task_id,
        cluster=cfg("ecs_cluster"),
        task_definition=cfg("dbt_task_family"),
        launch_type="FARGATE",
        network_configuration={
            "awsvpcConfiguration": {
                "subnets": cfg("task_subnets"),
                "securityGroups": [cfg("task_security_group")],
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={"containerOverrides": [{"name": cfg("dbt_container"), "command": command}]},
        awslogs_group=cfg("dbt_log_group"),
        awslogs_region=cfg("region"),
        awslogs_stream_prefix=cfg("dbt_log_prefix") + "/" + cfg("dbt_container"),
        deferrable=True,
        waiter_delay=15,
        waiter_max_attempts=240,
    )


with DAG(
    dag_id="elt_daily",
    description="Landing zone -> Snowflake RAW -> dbt build",
    schedule="0 5 * * *",
    start_date=datetime(2025, 1, 1, tzinfo=UTC),
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    render_template_as_native_obj=True,
    tags=["elt"],
) as dag:

    @task
    def platform_config() -> dict:
        return config.load_platform_config()

    @task
    def create_raw_tables() -> None:
        con = connect()
        try:
            cur = con.cursor()
            for entity in config.entities():
                cur.execute(config.ddl(entity))
        finally:
            con.close()

    @task
    def copy_into(entity: str, ds=None) -> int:
        con = connect()
        try:
            cur = con.cursor()
            cur.execute(copy_into_sql(entity, ds))
            return sum(row[3] for row in cur.fetchall() if row[1] == "LOADED")
        finally:
            con.close()

    config_ready = platform_config()

    check_partition = S3KeySensor.partial(
        task_id="check_partition",
        bucket_name=cfg("lake_bucket"),
        wildcard_match=True,
        mode="reschedule",
        poke_interval=300,
        timeout=6 * 60 * 60,
    ).expand(bucket_key=[f"landing/{e}/load_date={{{{ ds }}}}/*" for e in config.entities()])

    tables = create_raw_tables()
    loaded = copy_into.expand(entity=config.entities())
    freshness = dbt_task("dbt_source_freshness", ["source", "freshness"])
    build = dbt_task("dbt_build", ["build"])

    config_ready >> check_partition >> tables >> loaded >> freshness >> build
