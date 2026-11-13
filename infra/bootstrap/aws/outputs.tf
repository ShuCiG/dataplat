output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.bucket
}

output "terraform_plan_role_arn" {
  description = "Role for terraform plan on pull requests."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arns" {
  description = "Role for terraform apply, per environment."
  value       = { for env, role in aws_iam_role.terraform_apply : env => role.arn }
}

output "dbt_deploy_role_arns" {
  description = "Role for the dbt image deploy, per environment."
  value       = { for env, role in aws_iam_role.dbt_deploy : env => role.arn }
}
