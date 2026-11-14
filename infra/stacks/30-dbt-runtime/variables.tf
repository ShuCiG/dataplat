variable "project" {
  description = "Project name."
  type        = string
  default     = "dataplat"
}

variable "environment" {
  description = "Environment name. Set in infra/envs/<environment>.tfvars."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "Use a short lowercase name such as dev or prd."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "snowflake_account" {
  description = "Snowflake account identifier (<organization>-<account>). An address, not a credential: the task signs in with its AWS role."
  type        = string
}

variable "cpu" {
  description = "Fargate CPU units of the dbt task."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory of the dbt task, in MiB."
  type        = number
  default     = 1024
}

variable "image_tag_override" {
  description = "Run this image tag instead of the one in the SSM parameter. Empty means use the parameter."
  type        = string
  default     = ""
}
