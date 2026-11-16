# dataplat

A small cloud data platform: raw files land in S3, get loaded into Snowflake, are transformed with dbt into a dimensional model, and the whole thing is orchestrated by Airflow. Infrastructure is Terraform, dbt runs as a container on ECS Fargate, and nothing authenticates with a long-lived cloud key.

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
| `tools/verify/` | Post-deploy checks and one-off loaders |
| `docs/` | Architecture notes, runbook, ADRs |

## Local setup

Requirements: Docker, Terraform >= 1.10, AWS CLI v2, [uv](https://docs.astral.sh/uv/), [go-task](https://taskfile.dev/).

```bash
task setup   # install dev dependencies and git hooks
task lint    # run all linters
```

Run the data generator and the unit tests without any cloud access:

```bash
task test
task datagen -- --date 2025-03-15 --days 3
```

## Environments

Four environments, `dev`, `tst`, `stg` and `prd`, are the same Terraform stacks applied with a different
variable file. Only `dev` is changed by hand; the rest are changed by GitHub Actions, and `stg` and `prd`
wait for a reviewer. See [infra/README.md](infra/README.md) for the pipelines.

## Run the pipeline locally

Airflow runs in Docker on your machine and talks to the real AWS and Snowflake environment you choose with
`PLATFORM_ENV`. Setup is in [airflow/README.md](airflow/README.md); the short version:

```bash
cp airflow/.env.example airflow/.env   # fill in
task airflow:up                        # UI on http://localhost:8080
task airflow:test                      # DAG tests
```

When loading an empty environment, start from 2025-01-01, or the relationship tests on orders fail.

## More

- [docs/architecture.md](docs/architecture.md): data flow and access model
- [docs/runbook.md](docs/runbook.md): manual steps, failures, rollback
- [docs/adr/](docs/adr/): why things are the way they are

## Tear everything down

`task destroy -- <env>` shows what would be deleted; add `--execute` to delete it. The bootstrap
objects are removed by hand. Details: [Tear everything down](docs/runbook.md#tear-everything-down).
