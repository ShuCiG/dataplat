# dataplat

A small cloud data platform: raw files land in S3, get loaded into Snowflake, are transformed with dbt into a dimensional model, and the whole thing is orchestrated by Airflow. Infrastructure is Terraform, dbt runs as a container on ECS Fargate, and nothing authenticates with a long-lived cloud key.

> Work in progress. Sections below are filled in as each part lands.

## Architecture

```
 data generator
       |  parquet, load_date=YYYY-MM-DD
       v
 +-----------+   COPY INTO (storage integration)   +---------------------------+
 | S3 lake   | ----------------------------------> | Snowflake                 |
 | landing/  |                                     |  <ENV>_RAW.LANDING        |
 +-----------+                                     |  <ENV>_ANALYTICS.STAGING  |
       ^                                           |  ...INTERMEDIATE, MARTS   |
       | dbt artifacts                             +---------------------------+
       |                                                        ^
 +-----+--------------+   RunTask   +--------------------+      | workload identity
 | Airflow            | ----------> | ECS Fargate: dbt   | -----+ (no password)
 | DAG elt_daily      |             | image from ECR     |
 +--------------------+             +--------------------+
                                              ^
 GitHub Actions -- OIDC --> AWS IAM -- build/push ECR, terraform apply
```

## Repository layout

| Path | Contents |
|---|---|
| `infra/` | Terraform: AWS and Snowflake |
| `dbt/` | dbt project and its Docker image |
| `airflow/` | Local Airflow and DAGs |
| `tools/datagen/` | Synthetic data generator |
| `docs/` | Architecture notes, runbook, ADRs |

## Local setup

Requirements: Docker, Terraform >= 1.10, AWS CLI v2, [uv](https://docs.astral.sh/uv/), [go-task](https://taskfile.dev/).

```bash
task setup   # install dev dependencies and git hooks
task lint    # run all linters
```
