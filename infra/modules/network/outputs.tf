output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Ids of the public subnets."
  value       = aws_subnet.public[*].id
}

output "tasks_security_group_id" {
  description = "Security group for Fargate tasks."
  value       = aws_security_group.tasks.id
}
