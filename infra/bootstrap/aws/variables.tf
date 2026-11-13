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

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Prefix of the OIDC subject claim GitHub issues for the repository. Repositories with immutable
    subjects include numeric ids, e.g. repo:owner@123/name@456. Read it with:
    gh api repos/<owner>/<repo>/actions/oidc/customization/sub -q .sub_claim_prefix
  EOT
  type        = string

  validation {
    condition     = can(regex("^repo:[^/:*]+/[^/:*]+$", var.github_oidc_subject_prefix))
    error_message = "Must look like repo:owner/name or repo:owner@id/name@id, without wildcards."
  }
}

variable "environments" {
  description = "Deployment environments. Each gets its own apply and deploy role."
  type        = set(string)
  default     = ["dev", "tst", "stg", "prd"]
}

variable "sandbox_environments" {
  description = <<-EOT
    Environments people may change by hand. They get a <project>-<env>-developer role with the
    same permissions as the pipeline. Every other environment gets a read-only
    <project>-<env>-viewer role and can only be changed through its GitHub environment.
  EOT
  type        = set(string)
  default     = ["dev"]

  validation {
    condition     = length(setsubtract(var.sandbox_environments, var.environments)) == 0
    error_message = "Every sandbox environment must also be listed in environments."
  }
}
