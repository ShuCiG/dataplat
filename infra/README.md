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

A change to a stack or a module therefore reaches every environment, but never all at once. Anything
that should differ between environments has to be a variable and show up in `envs/`, which keeps the
differences few and visible.

## Promotion

`infra-apply` promotes one commit through the environments in order:

```
dev  ->  tst  ->  stg  ->  prd
```

Each environment is one run of `infra-deploy-env`: apply every stack, then verify. The next
environment starts only if the previous one succeeded, so a change that has not been proven in `dev`,
`tst` and `stg` cannot reach `prd`.

Verification after the apply:

1. Every stack plans clean again (`terraform plan -detailed-exitcode`), so the apply converged.
2. `tools/verify/verify_warehouse.py` checks the Snowflake access model: which roles each functional
   role bundles, that the transformer cannot write RAW, that analysts cannot reach RAW or staging,
   that nothing reaches into another environment, and that Snowflake can list the landing bucket.

Manual approval is configured on the GitHub environment, not in the workflow: `stg` and `prd` list
required reviewers, and the run waits there until they confirm. Checks that need a running
pipeline (dbt tests, DAG runs) are added to `infra-deploy-env` as those parts are built.

## dbt image deploy

`stacks/30-dbt-runtime` holds only the dbt task definition. It is applied by `dbt-deploy`, not by
`infra-apply`, because it changes with every image and the deploy role has no rights over the
rest of the platform.

`dbt-deploy` builds the image once (tag `git-<commit>`) and promotes that exact image through
`dev -> tst -> stg -> prd`. Per environment: push to that environment's registry, write the tag to
`/dataplat/<env>/dbt/image_tag`, apply the stack, then run `dbt debug` on ECS
(`tools/verify/run_dbt_task.py`). The next environment starts only if that run is green. It proves
the task starts, signs in to Snowflake with its AWS role and sees every object dbt needs.

Rolling back is re-running the workflow on an older commit: tags are immutable, so the old image is
still in the registry.

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
| `20-warehouse` | Snowflake warehouses, databases, roles and grants, service users (workload identity), S3 storage integration and landing stage | on merge, after `10-platform` of the same environment |

`20-warehouse` reads the AWS roles created by `10-platform`, so the pipeline applies both stacks
to one environment before it moves on to the next. It logs in to Snowflake with a GitHub OIDC
token and needs the repository secrets `SNOWFLAKE_ORGANIZATION_NAME` and
`SNOWFLAKE_ACCOUNT_NAME`. Pull requests only validate it (no Snowflake user trusts the pull
request subject, on purpose); the plan runs in the apply workflow behind the environment approval.

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

`20-warehouse` also needs a Snowflake login, taken from the environment:

```bash
export SNOWFLAKE_ORGANIZATION_NAME=... SNOWFLAKE_ACCOUNT_NAME=...
export SNOWFLAKE_USER=TERRAFORM_DEV SNOWFLAKE_AUTHENTICATOR=WORKLOAD_IDENTITY
export SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER=AWS   # with AWS_PROFILE=dataplat-dev
```

## Runtime configuration

Each environment publishes one SSM parameter, `/<project>/<env>/platform/config`, with the names
of everything workflow code needs: bucket, cluster, task family, subnets, log group. Pipelines
read it at run time, so DAG code contains no environment names and no resource identifiers.
