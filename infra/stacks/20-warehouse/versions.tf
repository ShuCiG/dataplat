terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.23"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bucket, region and the per-environment key are supplied at init time, see infra/README.md.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "20-warehouse"
    }
  }
}

# Account, user and authentication come from SNOWFLAKE_* environment variables, so the same
# configuration works from a workstation (AWS workload identity) and from the pipeline
# (GitHub OIDC workload identity). No password or key is involved in either case.
provider "snowflake" {
  role = "PLATFORM_ADMIN"
}
