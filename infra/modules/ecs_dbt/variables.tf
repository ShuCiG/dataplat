variable "name_prefix" {
  description = "Prefix for resource names, usually <project>-<env>."
  type        = string
}

variable "image_tag_parameter_name" {
  description = "SSM parameter that holds the currently deployed dbt image tag."
  type        = string
}

variable "lake_bucket_arn" {
  description = "ARN of the lake bucket. The task may write run artifacts under artifacts/dbt/."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the task log group."
  type        = number
  default     = 30
}
