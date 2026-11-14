output "task_definition_arn" {
  description = "Revision of the dbt task definition that was just registered."
  value       = aws_ecs_task_definition.dbt.arn
}

output "image" {
  description = "Image the task definition runs."
  value       = "${data.aws_ecr_repository.dbt.repository_url}:${local.image_tag}"
}
