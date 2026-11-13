output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "log_group_name" {
  description = "Log group of the dbt task."
  value       = aws_cloudwatch_log_group.dbt.name
}

output "log_group_arn" {
  description = "ARN of the dbt task log group."
  value       = aws_cloudwatch_log_group.dbt.arn
}

output "task_role_arn" {
  description = "ARN of the dbt task role."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the dbt task role."
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "ARN of the task execution role."
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Name of the task execution role."
  value       = aws_iam_role.execution.name
}
