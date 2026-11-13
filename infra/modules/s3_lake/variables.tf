variable "name_prefix" {
  description = "Prefix for resource names, usually <project>-<env>."
  type        = string
}

variable "noncurrent_version_days" {
  description = "Days to keep overwritten or deleted object versions."
  type        = number
  default     = 30
}

variable "artifact_retention_days" {
  description = "Days to keep run artifacts under artifacts/."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow destroying the bucket while it still holds objects. Never enable in production."
  type        = bool
  default     = false
}
