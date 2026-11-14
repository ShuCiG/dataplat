# Architecture

This document describes what exists today. It is updated in the same pull request as the change
it describes. Decisions and their reasons are in [adr/](adr/).

## Overview

```
 data generator
       |  parquet, load_date=YYYY-MM-DD
       v
 +-----------+   COPY INTO (storage integration)   +---------------------------+
 | S3 lake   | ----------------------------------> | Snowflake                 |
 | landing/  |                                     |  raw -> staging -> marts  |
 +-----------+                                     +---------------------------+
       ^                                                        ^
       | dbt artifacts                                          | workload identity
 +-----+--------------+   RunTask   +--------------------+      |
 | Airflow            | ----------> | ECS Fargate: dbt   | -----+
 +--------------------+             +--------------------+
                                              ^
 GitHub Actions -- OIDC --> AWS IAM -- terraform apply, image push
```

Status: AWS foundation, the data generator and the dbt project are in place. The dbt project is
checked by parsing only; it has not run against a warehouse yet. The Snowflake warehouse stack
(`20-warehouse`) is defined and applied to dev; Airflow and the image pipeline are not built.

## Environments

| Name | Purpose | Changed by | Data loss on destroy |
|---|---|---|---|
| `dev` | Where changes land first | pipeline, and people by hand | allowed |
| `tst` | Automated checks on a clean copy | pipeline only | allowed |
| `stg` | Configured like production; final verification | pipeline only | blocked |
| `prd` | Production | pipeline only | blocked |

All four live in one AWS account and one region (`eu-central-1`) and are separated by name
prefix (`dataplat-<env>-`) and by IAM. See [ADR 0003](adr/0003-single-account-environments.md).

### One definition, four environments

There is no per-environment copy of the infrastructure code. A stack in `infra/stacks/` is
applied once per environment with `infra/envs/<env>.tfvars` and a state key of
`<env>/<stack>/terraform.tfstate`. The variable files are the only place where environments may
differ, and today they differ in three values: VPC range, log retention, and whether data-holding
resources may be destroyed.

Consequences:

- A change to a stack or module reaches every environment. It cannot be applied to one and
  forgotten in another.
- A new difference between environments has to be introduced as a variable, so it is visible in
  review.
- Adding an environment is a new `.tfvars` file plus one entry in the bootstrap `environments`
  variable and in the workflow matrices.

### Rollout

On merge to `main`, `infra-apply` applies the same commit to `dev`, `tst`, `stg`, `prd`, in that
order, one at a time. A failure stops the rollout before the next environment.

## AWS resources per environment

Stack `10-platform`:

| Resource | Name | Notes |
|---|---|---|
| VPC, 2 public subnets, internet gateway | `dataplat-<env>` | No NAT gateway. See [ADR 0004](adr/0004-public-subnets-for-tasks.md) |
| Security group | `dataplat-<env>-tasks` | HTTPS out, nothing in |
| S3 bucket | `dataplat-<env>-lake-<suffix>` | Versioned, encrypted, TLS only, no public access. `landing/` and `artifacts/` |
| ECR repository | `dataplat-<env>-dbt` | Immutable tags, scan on push, last 20 images kept |
| ECS cluster | `dataplat-<env>` | Fargate only |
| Log group | `/ecs/dataplat-<env>/dbt` | Retention from `envs/<env>.tfvars` |
| SSM parameter | `/dataplat/<env>/dbt/image_tag` | Written by the image pipeline |
| SSM parameter | `/dataplat/<env>/platform/config` | Runtime configuration, see below |
| IAM role | `dataplat-<env>-dbt-task` | Identity of the dbt container |
| IAM role | `dataplat-<env>-dbt-task-execution` | Image pull and log delivery |
| IAM role | `dataplat-<env>-airflow-orchestrator` | Start and watch the dbt task, read `landing/` |

VPC ranges: `dev` 10.20.0.0/16, `tst` 10.21.0.0/16, `stg` 10.22.0.0/16, `prd` 10.23.0.0/16.

Account-wide, created once by `infra/bootstrap/aws`: the Terraform state bucket, the GitHub OIDC
provider, and the roles in the next section.

## Access model

### Pipeline roles

GitHub Actions holds no AWS keys. Each job exchanges a short-lived OIDC token for a role, and
each role trusts exactly one subject.

| Role | Trusted subject | Permissions |
|---|---|---|
| `dataplat-gha-terraform-plan` | pull requests of this repository | read only |
| `dataplat-gha-terraform-apply-<env>` | GitHub environment `<env>` | manage `dataplat-<env>-*` resources and the `<env>/` state prefix |
| `dataplat-gha-dbt-deploy-<env>` | GitHub environment `<env>` | push the image, write the image tag, register task definitions |

Apply roles are explicitly denied any change to the bootstrap roles, the OIDC provider, the
people roles and the state bucket configuration.

GitHub environments `tst`, `stg` and `prd` accept deployments from `main` only. A workflow on any
other branch cannot obtain their roles.

### People roles

| Environment | Role | Permissions |
|---|---|---|
| `dev` | `dataplat-dev-developer` | same policy as the `dev` pipeline: full control of `dev` resources |
| `tst`, `stg`, `prd` | `dataplat-<env>-viewer` | read only: describe resources, read logs, lake objects and parameters of that environment |

Outside `dev` there is no role a person can assume that changes anything. The only identities
with write access to `tst`, `stg` and `prd` are the pipeline roles.

Local profiles follow the same naming, each assuming its role from the base credentials:

```ini
[profile dataplat-dev]
role_arn       = arn:aws:iam::<account>:role/dataplat-dev-developer
source_profile = <base profile>
region         = eu-central-1
```

```bash
aws s3 ls --profile dataplat-dev    # read and write
aws s3 ls --profile dataplat-prd    # read only
```

### Known gaps

- The account administrator can still change any environment directly. The model constrains the
  day-to-day roles, not the break-glass identity.
- Apply roles may create IAM roles named `dataplat-<env>-*` without a permissions boundary, so a
  workflow running in an environment could grant such a role more than the apply role itself
  has. Closing this needs a boundary policy enforced on role creation.
- Required reviewers on the `prd` environment and branch protection on `main` need a public
  repository or a paid plan. They are not enabled yet.

## Secrets

The design goal is to have as few secrets as possible: pipelines use OIDC, and the dbt task uses
workload identity. Where a secret cannot be avoided (a private key for a service user, for
example) these rules apply:

- It lives in AWS Secrets Manager under `dataplat/<env>/<name>`, one secret per environment.
- Terraform creates the secret container and the IAM permission to read it. It never sets or
  reads the value, so no secret ends up in state, in a plan or in a workflow log.
- The value is put there by a person, once, following the step-by-step procedure in
  `docs/runbook.md`.
- Consumers read it at run time through their IAM role. Nothing is copied into GitHub secrets,
  `.env` files in the repository, or container images.

Non-secret configuration (names, ARNs, the image tag) stays in SSM Parameter Store.

No secrets exist yet. Terraform reaches Snowflake with workload identity as well (the dev
developer AWS role from a workstation, GitHub OIDC from the pipeline), so the warehouse bootstrap
adds none. See [infra/bootstrap/snowflake](../infra/bootstrap/snowflake/README.md).

## Runtime configuration

Workflow code must not know which environment it runs in or what its resources are called. Each
environment publishes one JSON document to SSM at `/dataplat/<env>/platform/config`:

```json
{
  "environment": "dev",
  "region": "eu-central-1",
  "lake_bucket": "...",
  "ecs_cluster": "...",
  "dbt_task_family": "...",
  "dbt_container": "dbt",
  "dbt_log_group": "...",
  "dbt_log_prefix": "dbt",
  "task_subnets": ["...", "..."],
  "task_security_group": "..."
}
```

A deployment of the orchestrator is told one thing, the name of its environment, and reads
everything else from this parameter. The same DAG files run unchanged in every environment.

## CI/CD

| Workflow | Trigger | Does |
|---|---|---|
| `ci` | every pull request, push to `main` | linters, unit tests, dbt project parse |
| `infra-plan` | pull requests touching `infra/` | fmt, validate, tflint and plan for bootstrap and for every environment |
| `infra-apply` | merge to `main` touching stacks, modules or env files | rollout `dev` -> `tst` -> `stg` -> `prd` |

Repository settings the workflows rely on are listed in
[infra/bootstrap/aws/README.md](../infra/bootstrap/aws/README.md).
