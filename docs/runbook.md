# Runbook

What to do by hand, and what to do when something breaks. Everything else is automated; see
`architecture.md` for how the pieces fit and `infra/README.md` for the pipelines.

Replace `<env>` with `dev`, `tst`, `stg` or `prd`. `tst`, `stg` and `prd` are changed only by
GitHub Actions (ADR 5); the commands below that write to an environment are for `dev`.

## Give a person access

People get roles, never users with keys.

**AWS.** The bootstrap stack (`infra/bootstrap/aws`) creates `dataplat-<env>-developer` for the
sandbox environments and `dataplat-<env>-viewer` for the rest. Anyone in the account who is allowed
to assume a role can use them; the role names are the only thing to hand over. Which environments
are sandboxes is the bootstrap variable `sandbox_environments`. Changes there are applied by a
human with admin credentials.

**Snowflake.** `20-warehouse` creates `<ENV>_DEVELOPER` in sandboxes (LOADER, TRANSFORMER and
ANALYST bundled) and `<ENV>_VIEWER` elsewhere (ANALYST only). Grant it to the person's user:

```sql
GRANT ROLE DEV_DEVELOPER TO USER <name>;
GRANT ROLE PRD_VIEWER    TO USER <name>;
```

Run it with a role that may manage grants. Grants made by hand are not in Terraform and are not
touched by it.

## Secrets

Today nothing needs a secret: pipelines use GitHub OIDC, dbt and Airflow sign in to Snowflake with
their AWS role (workload identity), and the Terraform users do the same. If a key-pair user is
added later, ADR 6 applies:

1. Terraform creates the secret container `dataplat/<env>/<name>` and the IAM grants, never the
   value.
2. A person generates the key pair locally, uploads the private key with
   `aws secretsmanager put-secret-value`, and registers the public key on the Snowflake user
   (`ALTER USER ... SET RSA_PUBLIC_KEY = '...'`).
3. Rotation: generate a new pair, set it as `RSA_PUBLIC_KEY_2`, upload the new private key, check a
   login, then `UNSET RSA_PUBLIC_KEY`. Delete the local copies.

## Run Airflow locally

See `airflow/README.md`. In short: fill `airflow/.env`, `task airflow:up`, open
http://localhost:8080.

Backfill a day: unpause `elt_daily` and trigger it with that logical date. The day's files must
already be in `landing/`. A paused DAG does not start queued runs. Unpausing also creates today's
scheduled run; if today's files do not exist its sensors wait up to 6 hours, so mark that run
failed. Loading is idempotent, so a rerun of a date loads 0 rows.

To generate and upload data for a date:

```bash
task datagen -- --date 2025-03-15 --days 3
task datagen:upload -- --date 2025-03-15 --bucket <lake bucket>
```

Load from 2025-01-01 when starting from empty, or the relationship tests on orders fail.

## Roll back the dbt image

Tags are immutable (`git-<commit>`), so an old image is still in the registry. Re-run the
`dbt-deploy` workflow on the older commit. It promotes that image through
`dev -> tst -> stg -> prd` again, with approval at `stg` and `prd`, and gates each step on
`dbt debug` on ECS. The next DAG run uses it, because the task definition reads the tag from
`/dataplat/<env>/dbt/image_tag`.

## When a run fails

Open the task log in Airflow first. Tasks retry 3 times with growing delays, so a red task has
already failed 4 times. Fixing the cause and clearing the task (not the run) continues from there.

| Task | Typical cause | What to do |
|---|---|---|
| `check_partition` waits | The day's files are not in `landing/` yet, or the date has no data | Check `s3://<lake bucket>/landing/<entity>/load_date=<date>/`. Generate or upload the data. It gives up after 6 hours. |
| `create_raw_tables` / `copy_into`: `No AWS region was found` | `AWS_REGION` missing in the container | Set it in `airflow/.env`, `task airflow:up` again. |
| `copy_into`: login or role error | The AWS profile cannot assume the orchestrator role, or `<ENV>_AIRFLOW_SVC` lost its binding | See "Snowflake login fails" below. |
| `copy_into`: loads 0 rows for a new day | Files for that partition were already loaded, or the path differs | Check the stage listing: `LIST @DEV_RAW.LANDING.S3_LANDING/<entity>/load_date=<date>/`. 0 on a rerun is correct. |
| `copy_into`: table not found | Tables created by another role are invisible to LOADER | Drop them and let `create_raw_tables` recreate them as the LOADER role. |
| `dbt_source_freshness` | Landing data is older than the threshold (warns after 30 h, errors after 54 h) | Load the missing days. |
| `dbt_build` | A model or test failed | Read the log printed by the task (it includes the dbt output). Fix on a branch; the next deploy picks it up. |

## Snowflake login fails (workload identity)

dbt on ECS and Airflow sign in with `<ENV>_DBT_SVC` and `<ENV>_AIRFLOW_SVC`. When a login fails:

1. Confirm the AWS side works: `aws sts get-caller-identity` with the same profile or task role,
   and that its ARN is the one the Snowflake user is bound to.
2. Inspect the user: `DESCRIBE USER <ENV>_DBT_SVC;` and check the `WORKLOAD_IDENTITY` property.
3. Read the reason: `SELECT * FROM TABLE(INFORMATION_SCHEMA.LOGIN_HISTORY_BY_USER('<ENV>_DBT_SVC'))
   ORDER BY EVENT_TIMESTAMP DESC;`.
4. If the binding drifted, run `terraform plan` for `20-warehouse` in that environment; it shows the
   difference.

For a local session as the Terraform user, set `SNOWFLAKE_USER=TERRAFORM_DEV`,
`SNOWFLAKE_AUTHENTICATOR=WORKLOAD_IDENTITY`, `SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER=AWS` and use an
`AWS_PROFILE` for that environment.

## Run the dbt task once by hand

```bash
python tools/verify/run_dbt_task.py dev debug --connection
python tools/verify/run_dbt_task.py dev build --select stg_landing__orders
```

It starts the task in that environment, waits, prints the log and returns the exit code.

## Tear everything down

One environment is removed with `tools/teardown/teardown.py`. It destroys the three stacks in the
order that works, because later stacks read from earlier ones: `30-dbt-runtime`, `20-warehouse`,
then `10-platform`.

Set the shell up as for a manual Terraform run (an `AWS_PROFILE` for the environment, and
`SNOWFLAKE_USER`, `SNOWFLAKE_AUTHENTICATOR`, `SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER`,
`SNOWFLAKE_ORGANIZATION_NAME`, `SNOWFLAKE_ACCOUNT_NAME`), then:

```bash
task destroy -- dev                 # dry run: terraform plan -destroy for each stack
task destroy -- dev --execute       # deletes it, after you type the environment name
task destroy -- prd --execute --allow-data-loss
```

- Without `--execute` nothing is changed.
- Environments with `allow_data_loss = false` (`stg`, `prd`) refuse `--execute` unless you also pass
  `--allow-data-loss`. The script then applies that flag first, because the bucket and the image
  repository read it from the state when they are deleted.
- Locally only `dev` has a Terraform user in Snowflake (`TERRAFORM_DEV`). For `tst`, `stg` and `prd`
  the Snowflake user trusts only GitHub Actions, so their warehouse stack cannot be destroyed from a
  workstation; run the script with credentials that can manage that environment's Snowflake objects.
- If a stack fails, fix the cause and run the same command again: finished stacks have an empty state
  and are skipped quickly.

What the script leaves, to remove by hand once every environment you want gone is gone:

1. `infra/bootstrap/aws`, last and with admin credentials. It holds the state bucket, so destroy it
   only after every other stack is gone.
2. The Snowflake bootstrap objects: the `PLATFORM_ADMIN` role and the `TERRAFORM_DEV` and
   `TERRAFORM_GHA_<ENV>` users created by `infra/bootstrap/snowflake/bootstrap.sql`, and the account
   resource monitor `DATAPLAT_ACCOUNT` if nothing else in the account needs it.

Do not touch Snowflake objects that are not named `<ENV>_*` or `PLATFORM_*`: the account may hold
other projects.
