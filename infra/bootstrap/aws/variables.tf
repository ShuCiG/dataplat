variable "project" {
  description = "Project name, used as a prefix for every resource."
  type        = string
  default     = "dataplat"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Must be in the form owner/name."
  }
}

variable "environments" {
  description = "Deployment environments. Each gets its own apply and deploy role."
  type        = set(string)
  default     = ["dev", "prod"]
}
