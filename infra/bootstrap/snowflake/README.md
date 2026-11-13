# bootstrap/snowflake

One SQL script, run once by a person as `ACCOUNTADMIN`. After it, Terraform manages everything
and `ACCOUNTADMIN` is not needed again.

## What it creates

| Object | Purpose |
|---|---|
| Role `PLATFORM_ADMIN` | Creates databases, warehouses, roles, users, integrations; manages grants |
| Resource monitor `DATAPLAT_ACCOUNT` | Account-wide monthly credit cap; suspends warehouses at 100% |
| User `TERRAFORM_DEV` | Terraform run from a workstation, authenticated as the AWS role `dataplat-dev-developer` |
| Users `TERRAFORM_GHA_<ENV>` | Terraform in GitHub Actions, each bound to one GitHub environment |

All users are `TYPE = SERVICE` and authenticate with workload identity. None has a password or
key, so there is nothing to store or rotate.

## How to run it

1. Sign in to Snowsight as a user that can use `ACCOUNTADMIN`.
2. **Projects -> Worksheets -> +** to open a new SQL worksheet.
3. Paste `bootstrap.sql` and replace the placeholders:
   - `<AWS_ACCOUNT_ID>`: `aws sts get-caller-identity --query Account --output text`
   - `<OIDC_SUBJECT_PREFIX>`:
     `gh api repos/<owner>/<repo>/actions/oidc/customization/sub -q .sub_claim_prefix`
4. Open the menu next to the run button and choose **Run All**.
5. The last statement lists the five `TERRAFORM_*` users.

## Verifying

From a workstation, with the dev profile active:

```bash
export AWS_PROFILE=dataplat-dev
export SNOWFLAKE_ORGANIZATION_NAME=<organization>   # first part of the account identifier
export SNOWFLAKE_ACCOUNT_NAME=<account>             # second part
export SNOWFLAKE_USER=TERRAFORM_DEV
export SNOWFLAKE_ROLE=PLATFORM_ADMIN
export SNOWFLAKE_AUTHENTICATOR=WORKLOAD_IDENTITY
export SNOWFLAKE_WORKLOAD_IDENTITY_PROVIDER=AWS
```

A `terraform plan` of any Snowflake stack then connects without further credentials.

## Limits of this setup

- `PLATFORM_ADMIN` is account-wide: Snowflake account privileges cannot be scoped to an
  environment by name. A CI job for `dev` could in principle alter `prd` objects. Separation
  between environments is enforced on the GitHub side (who may run in which environment), not by
  Snowflake privileges.
- Pull request plans do not connect to Snowflake; there is no user bound to the pull request
  subject. Snowflake changes are planned and applied in the environment jobs.
