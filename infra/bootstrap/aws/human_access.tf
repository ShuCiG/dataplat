# Roles for people, one per environment.
#
#   sandbox environments   <project>-<env>-developer   same permissions as the pipeline
#   everything else        <project>-<env>-viewer      read only
#
# Outside the sandbox there is no role a person can assume that changes anything: the only
# identities with write access are the pipeline roles, and those trust nothing but the
# matching GitHub environment.

locals {
  sandbox_environments   = var.sandbox_environments
  protected_environments = setsubtract(var.environments, var.sandbox_environments)
}

# Principals of this account that have been granted sts:AssumeRole on the role.
data "aws_iam_policy_document" "trust_account" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["${local.iam_prefix}:root"]
    }
  }
}

resource "aws_iam_role" "developer" {
  for_each = local.sandbox_environments

  name                 = "${var.project}-${each.key}-developer"
  description          = "Hands-on access to ${each.key}: same permissions as the ${each.key} pipeline."
  assume_role_policy   = data.aws_iam_policy_document.trust_account.json
  max_session_duration = 43200
}

resource "aws_iam_role_policy_attachment" "developer" {
  for_each = local.sandbox_environments

  role       = aws_iam_role.developer[each.key].name
  policy_arn = aws_iam_policy.terraform_apply[each.key].arn
}

data "aws_iam_policy_document" "viewer" {
  for_each = local.protected_environments

  statement {
    sid = "DescribePlatform"
    actions = [
      "ec2:Describe*",
      "ecr:BatchGetImage",
      "ecr:Describe*",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:List*",
      "ecs:Describe*",
      "ecs:List*",
      "logs:Describe*",
      "s3:GetBucket*",
      "s3:ListAllMyBuckets",
      "ssm:DescribeParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadLogs"
    actions   = ["logs:FilterLogEvents", "logs:GetLogEvents", "logs:StartQuery", "logs:GetQueryResults"]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/ecs/${var.project}-${each.key}/*"]
  }

  statement {
    sid       = "ReadLake"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:GetObjectVersion"]
    resources = ["arn:${local.partition}:s3:::${var.project}-${each.key}-lake-*", "arn:${local.partition}:s3:::${var.project}-${each.key}-lake-*/*"]
  }

  statement {
    sid       = "ReadParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/${var.project}/${each.key}/*"]
  }

  statement {
    sid       = "ReadEnvironmentRoles"
    actions   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"]
    resources = ["${local.iam_prefix}:role/${var.project}-${each.key}-*"]
  }
}

resource "aws_iam_policy" "viewer" {
  for_each = local.protected_environments

  name   = "${var.project}-${each.key}-viewer"
  policy = data.aws_iam_policy_document.viewer[each.key].json
}

resource "aws_iam_role" "viewer" {
  for_each = local.protected_environments

  name                 = "${var.project}-${each.key}-viewer"
  description          = "Read-only access to ${each.key}. Changes go through the ${each.key} GitHub environment."
  assume_role_policy   = data.aws_iam_policy_document.trust_account.json
  max_session_duration = 43200
}

resource "aws_iam_role_policy_attachment" "viewer" {
  for_each = local.protected_environments

  role       = aws_iam_role.viewer[each.key].name
  policy_arn = aws_iam_policy.viewer[each.key].arn
}
