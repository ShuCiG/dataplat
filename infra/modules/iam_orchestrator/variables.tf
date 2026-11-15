variable "name_prefix" {
  description = "Prefix for resource names, usually <project>-<env>."
  type        = string
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary attached to the role this module creates."
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster the orchestrator may run tasks on."
  type        = string
}

variable "task_family" {
  description = "Task definition family the orchestrator may run."
  type        = string
}

variable "passable_role_arns" {
  description = "Task and execution role ARNs the orchestrator hands to ECS."
  type        = list(string)
}

variable "log_group_arn" {
  description = "Log group the orchestrator reads task output from."
  type        = string
}

variable "readable_parameter_arns" {
  description = "SSM parameters the orchestrator may read."
  type        = list(string)
  default     = []
}

variable "lake_bucket_arn" {
  description = "Lake bucket. The orchestrator may list and read landing/."
  type        = string
}
