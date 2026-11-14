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

variable "sandbox" {
  description = "Whether people may write to this environment. Sandboxes get a DEVELOPER role, all others a read-only VIEWER role."
  type        = bool
  default     = false
}

variable "warehouse_size" {
  description = "Size of the environment's warehouses."
  type        = string
  default     = "XSMALL"
}

variable "warehouse_auto_suspend_seconds" {
  description = "Idle seconds before a warehouse suspends."
  type        = number
  default     = 60
}

variable "data_retention_days" {
  description = "Time travel retention for the environment's databases."
  type        = number
  default     = 1
}
