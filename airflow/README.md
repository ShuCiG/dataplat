# airflow

Local Airflow 3 (Docker Compose, LocalExecutor) and the `elt_daily` DAG. One image and one set of
DAG files serve every environment: `PLATFORM_ENV` in `.env` picks the one to drive, and all other
settings are read from SSM Parameter Store for that environment.

## elt_daily

Daily at 05:00 UTC, for the partition `load_date={{ ds }}`:

1. `platform_config`: read the environment's settings from SSM.
2. `check_partition`: wait for the files of each entity in `landing/` (S3 sensor, reschedule mode,
   checks every 5 minutes, gives up after 6 hours).
3. `create_raw_tables`: create the landing tables if they are missing.
4. `copy_into`: one task per entity, `COPY INTO` from the external stage. Snowflake remembers
   which files a table has loaded, so a rerun of the same partition loads 0 rows.
5. `dbt_source_freshness`, then `dbt_build`: run as a task on ECS Fargate with the dbt image.

Snowflake login uses the AWS role (workload identity) as `<ENV>_AIRFLOW_SVC` with the
`<ENV>_LOADER` role. There is no password or key anywhere.

## Run it

1. Copy `.env.example` to `.env` and fill in the Snowflake account name.
2. Make sure `~/.aws/config` has the profile named in `.env` (it assumes
   `dataplat-<env>-airflow-orchestrator`).
3. `task airflow:up`, then open http://localhost:8080 (no login locally).
4. DAGs start paused. To load a past date, unpause the DAG and trigger it with that logical date.
   A paused DAG does not start queued runs.

Unpausing also creates the scheduled run for today. If today's files do not exist, its sensors
wait. Mark that run failed or generate the data (`task datagen`, `task datagen:upload`).

`task airflow:test` runs the tests in the same image CI uses.
