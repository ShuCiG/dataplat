# bootstrap/aws

Resources that have to exist before anything else can be automated:

- S3 bucket for Terraform state (versioned, encrypted, TLS only, native lockfile locking)
- GitHub OIDC identity provider
- CI roles, each trusting one exact OIDC subject

| Role | Assumable from | Can do |
|---|---|---|
| `<project>-gha-terraform-plan` | pull requests of the repository | read only |
| `<project>-gha-terraform-apply-<env>` | GitHub environment `<env>` | manage the platform resources of that environment |
| `<project>-gha-dbt-deploy-<env>` | GitHub environment `<env>` | push the dbt image, record its tag, register a task definition revision |

The apply roles are explicitly denied any change to the bootstrap roles, the OIDC provider and the state bucket configuration. Changes to this stack are applied by a human with admin credentials.

## First apply

The state bucket is created by this stack, so the first run keeps state locally and then moves it.

```bash
cd infra/bootstrap/aws
prefix=$(gh api repos/<owner>/<repo>/actions/oidc/customization/sub -q .sub_claim_prefix)
printf 'github_oidc_subject_prefix = "%s"\n' "$prefix" > terraform.tfvars

# 1. local state
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init
terraform apply

# 2. move state into the new bucket
rm backend_override.tf
printf 'bucket = "%s"\nregion = "<region>"\n' "$(terraform output -raw state_bucket)" > ../../backend.hcl
terraform init -migrate-state -backend-config=../../backend.hcl
rm terraform.tfstate*
```

`backend.hcl`, `terraform.tfvars` and `*_override.tf` are git-ignored. Every other stack is initialised with the same `-backend-config=<path>/backend.hcl`.

## GitHub settings

After the apply, store the outputs in the repository:

| Kind | Name | Scope | Value |
|---|---|---|---|
| variable | `AWS_REGION` | repository | region |
| variable | `GH_OIDC_SUBJECT_PREFIX` | repository | same value as `github_oidc_subject_prefix` |
| variable | `TF_STATE_BUCKET` | repository | `state_bucket` |
| secret | `AWS_ROLE_TERRAFORM_PLAN` | repository | `terraform_plan_role_arn` |
| secret | `AWS_ROLE_TERRAFORM_APPLY` | environment | `terraform_apply_role_arns[<env>]` |
| secret | `AWS_ROLE_DBT_DEPLOY` | environment | `dbt_deploy_role_arns[<env>]` |

Role ARNs are not sensitive, but storing them as secrets keeps the account id out of workflow logs.
