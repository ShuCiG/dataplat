# infra

Terraform for AWS and Snowflake.

| Path | Purpose |
|---|---|
| `bootstrap/aws` | State bucket, GitHub OIDC provider, CI roles. Applied once by hand. |
| `bootstrap/snowflake` | One-off SQL run as `ACCOUNTADMIN` to create the Terraform role and user. |
| `modules/` | Reusable modules, parameterised by environment. |
| `live/<env>/10-platform` | Network, S3, ECR, ECS cluster, IAM, Snowflake objects and RBAC. |
| `live/<env>/20-dbt-runtime` | ECS task definition for dbt. Applied on every dbt deploy. |

State lives in S3 with native lockfile locking.
