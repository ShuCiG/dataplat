# infra

Terraform for AWS and Snowflake.

| Path | Purpose |
|---|---|
| `bootstrap/aws` | State bucket, GitHub OIDC provider, CI roles. Applied once by hand. |
| `bootstrap/snowflake` | One-off SQL run as `ACCOUNTADMIN` to create the Terraform role and user. |
| `modules/` | Reusable building blocks. |
| `stacks/` | Root modules. Each stack is written once and applied to every environment. |
| `envs/<env>.tfvars` | The only place where environments are allowed to differ. |

## One stack, many environments

There is no per-environment copy of the code. Every environment is the same stack applied with a
different variable file and a different state key:

```
stacks/10-platform  +  envs/dev.tfvars   ->  state key dev/10-platform/terraform.tfstate
stacks/10-platform  +  envs/prd.tfvars  ->  state key prd/10-platform/terraform.tfstate
```

A change to a stack or a module therefore reaches every environment: CI rolls the same commit
through `dev`, `tst`, `stg` and `prd` in that order and stops at the first failure. Anything that should differ between environments
has to be a variable and show up in `envs/`, which keeps the differences few and visible.

## Environments

| Name | Purpose |
|---|---|
| `dev` | Where changes land first. Disposable. |
| `tst` | Automated checks on a clean copy. Disposable. |
| `stg` | Configured like production; final verification. |
| `prd` | Production. |

Adding an environment means adding `envs/<name>.tfvars`, listing it in the bootstrap
`environments` variable and in the workflow matrices. No stack code changes.

## Stacks

| Stack | Contents | Applied |
|---|---|---|
| `10-platform` | Network, lake bucket, ECR, ECS cluster, task roles, orchestrator role, runtime config | on merge, when `infra/` changes |

## Running locally

`backend.hcl` (git-ignored, created during bootstrap) holds the state bucket and region.

```bash
cd infra/stacks/10-platform
ENV=dev
terraform init -reconfigure \
  -backend-config=../../backend.hcl \
  -backend-config="key=$ENV/10-platform/terraform.tfstate"
terraform plan -var-file=../../envs/$ENV.tfvars
```

Use `-reconfigure` whenever you switch environments: the backend key is part of the init.

## Runtime configuration

Each environment publishes one SSM parameter, `/<project>/<env>/platform/config`, with the names
of everything workflow code needs: bucket, cluster, task family, subnets, log group. Pipelines
read it at run time, so DAG code contains no environment names and no resource identifiers.
