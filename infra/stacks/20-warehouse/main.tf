locals {
  name_prefix = "${var.project}-${var.environment}"
  env         = upper(var.environment)

  platform = jsondecode(data.aws_ssm_parameter.platform.value)

  lake_bucket = local.platform.lake_bucket
  landing_url = "s3://${local.lake_bucket}/landing/"
}

# Names of the AWS resources this stack connects to come from the platform stack.
data "aws_ssm_parameter" "platform" {
  name = "/${var.project}/${var.environment}/platform/config"
}

data "aws_iam_role" "dbt_task" {
  name = "${local.name_prefix}-dbt-task"
}

data "aws_iam_role" "orchestrator" {
  name = "${local.name_prefix}-airflow-orchestrator"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# --- warehouses ------------------------------------------------------------------------------
# One per workload, so loading, transformation and reporting never queue behind each other
# and their cost can be told apart.

resource "snowflake_warehouse" "this" {
  for_each = {
    LOADING      = "COPY INTO from the landing zone."
    TRANSFORMING = "dbt runs."
    REPORTING    = "Analysts and BI tools."
  }

  name                = "${local.env}_${each.key}_WH"
  comment             = each.value
  warehouse_size      = var.warehouse_size
  auto_suspend        = var.warehouse_auto_suspend_seconds
  auto_resume         = "true"
  initially_suspended = true
}

# --- databases and schemas -------------------------------------------------------------------

resource "snowflake_database" "raw" {
  name                        = "${local.env}_RAW"
  comment                     = "Data as delivered by source systems. Append only."
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "landing" {
  database = snowflake_database.raw.name
  name     = "LANDING"
  comment  = "One table per entity, loaded from the S3 landing zone."
}

resource "snowflake_database" "analytics" {
  name                        = "${local.env}_ANALYTICS"
  comment                     = "Models built by dbt."
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "analytics" {
  for_each = {
    STAGING      = "Cleaned, deduplicated source tables."
    INTERMEDIATE = "Shared building blocks. Not for consumers."
    MARTS        = "Dimensions and facts for analysis."
  }

  database = snowflake_database.analytics.name
  name     = each.key
  comment  = each.value
}
