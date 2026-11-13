variable "project" {
  description = "Project name."
  type        = string
  default     = "dataplat"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}
