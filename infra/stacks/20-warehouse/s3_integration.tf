# Snowflake reads the landing zone by assuming an AWS role. The trust is mutual:
#
#   Snowflake side   the integration may only use this one role and this one bucket prefix
#   AWS side         the role may only be assumed by Snowflake's IAM user for this account,
#                    and only when it presents our external id
#
# The role ARN is built from its name so the integration can be created before the role;
# the role's trust policy then uses the IAM user that Snowflake reports back.

locals {
  s3_role_name = "${local.name_prefix}-snowflake-s3"
  s3_role_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.s3_role_name}"
}

resource "random_id" "external_id" {
  byte_length = 16
}

resource "snowflake_storage_integration_aws" "landing" {
  name    = "${local.env}_S3_LANDING"
  comment = "Read access to the ${var.environment} landing zone."
  enabled = true

  storage_provider          = "S3"
  storage_aws_role_arn      = local.s3_role_arn
  storage_aws_external_id   = random_id.external_id.hex
  storage_allowed_locations = [local.landing_url]
}

data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration_aws.landing.describe_output[0].iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [random_id.external_id.hex]
    }
  }
}

resource "aws_iam_role" "snowflake_s3" {
  name               = local.s3_role_name
  description        = "Assumed by Snowflake to read the landing zone."
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json
}

data "aws_iam_policy_document" "snowflake_s3" {
  statement {
    sid       = "ReadLanding"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.lake_bucket}/landing/*"]
  }

  statement {
    sid       = "ListLanding"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.lake_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["landing/*"]
    }
  }
}

resource "aws_iam_role_policy" "snowflake_s3" {
  name   = "read-landing"
  role   = aws_iam_role.snowflake_s3.id
  policy = data.aws_iam_policy_document.snowflake_s3.json
}

resource "snowflake_file_format_parquet" "landing" {
  database = snowflake_database.raw.name
  schema   = snowflake_schema.landing.name
  name     = "PARQUET"
  comment  = "Parquet files as written by the source extracts."
}

resource "snowflake_stage_external_s3" "landing" {
  database = snowflake_database.raw.name
  schema   = snowflake_schema.landing.name
  name     = "S3_LANDING"
  comment  = "Landing zone of the ${var.environment} lake bucket."

  url                 = local.landing_url
  storage_integration = snowflake_storage_integration_aws.landing.name

  file_format {
    format_name = snowflake_file_format_parquet.landing.fully_qualified_name
  }

  depends_on = [aws_iam_role_policy.snowflake_s3]
}
