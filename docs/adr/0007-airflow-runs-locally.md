# 7. Airflow runs locally in Docker Compose

Date: 2026-11-16. Status: accepted.

## Context

The managed Airflow service on AWS has a fixed monthly cost that is far above everything else in
the project, and it runs whether or not a DAG is scheduled. The project has to stay cheap.

## Decision

Airflow 3 runs in Docker Compose on a developer machine (`airflow/`), with the `LocalExecutor`.
The environment it works against is chosen with `PLATFORM_ENV`. The DAG reads all names and ARNs
from the environment's SSM configuration, so the DAG code does not change between environments.
dbt itself does not run in Airflow: the DAG starts an ECS task.

## Consequences

- No fixed cost. Airflow does not run while the machine is off, so scheduled runs are missed;
  `catchup=False` means they are not replayed, and a missed day is loaded by running the DAG for
  that date by hand.
- A paused DAG does not start queued manual runs, and unpausing creates a scheduled run whose
  sensors wait. The runbook describes how to handle both.
- Moving to the managed service later needs a module for it, DAGs synced to S3 from CI, and the
  orchestrator role as its execution role. The DAG code does not change.
