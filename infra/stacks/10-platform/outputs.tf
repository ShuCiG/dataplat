output "lake_bucket" {
  description = "Lake bucket name."
  value       = module.lake.bucket_name
}

output "ecr_repository_url" {
  description = "dbt image repository."
  value       = module.dbt_image.repository_url
}

output "ecs_cluster" {
  description = "ECS cluster name."
  value       = module.ecs_dbt.cluster_name
}

output "dbt_task_family" {
  description = "Task definition family of the dbt task."
  value       = local.dbt_family
}

output "dbt_log_group" {
  description = "Log group of the dbt task."
  value       = module.ecs_dbt.log_group_name
}

output "dbt_task_role_arn" {
  description = "Task role ARN. The warehouse trusts this ARN for workload identity."
  value       = module.ecs_dbt.task_role_arn
}

output "task_subnet_ids" {
  description = "Subnets to run tasks in."
  value       = module.network.public_subnet_ids
}

output "task_security_group_id" {
  description = "Security group to run tasks with."
  value       = module.network.tasks_security_group_id
}

output "runtime_config_parameter" {
  description = "SSM parameter with the runtime configuration for workflow code."
  value       = aws_ssm_parameter.runtime_config.name
}

output "orchestrator_role_arn" {
  description = "Role the orchestrator assumes."
  value       = module.orchestrator.role_arn
}
