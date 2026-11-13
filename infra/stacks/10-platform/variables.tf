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

variable "vpc_cidr" {
  description = "CIDR block of the environment VPC. Kept distinct per environment so they can be peered later."
  type        = string
}

variable "allow_data_loss" {
  description = "Let terraform destroy delete the lake bucket and image repository even when they hold data."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of task logs."
  type        = number
  default     = 30
}
