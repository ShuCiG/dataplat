# GitHub Actions authenticates to AWS with short-lived OIDC tokens. No access keys are stored
# in GitHub. Every role pins both the audience and the exact subject it trusts.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  iam_prefix = "arn:${local.partition}:iam::${local.account_id}"

  github_issuer = "token.actions.githubusercontent.com"
  state_bucket  = aws_s3_bucket.state.arn
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust_pull_request" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:sub"
      values   = ["${var.github_oidc_subject_prefix}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_environment" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:sub"
      values   = ["${var.github_oidc_subject_prefix}:environment:${each.key}"]
    }
  }
}

# --- terraform plan: read-only, usable from any pull request of the repository ---------------

resource "aws_iam_role" "terraform_plan" {
  name                 = "${var.project}-gha-terraform-plan"
  description          = "Read-only role for terraform plan on pull requests."
  assume_role_policy   = data.aws_iam_policy_document.trust_pull_request.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_plan_read_only" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# --- terraform apply: one role per environment ----------------------------------------------

data "aws_iam_policy_document" "terraform_apply" {
  for_each = var.environments

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.state_bucket]
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket}/${each.key}/*"]
  }

  # Services the platform is built from. IAM is handled separately below.
  statement {
    sid = "PlatformServices"
    actions = [
      "ec2:*",
      "ecr:*",
      "ecs:*",
      "logs:*",
      "s3:*",
      "ssm:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "ProjectRolesAndPolicies"
    actions   = ["iam:*"]
    resources = ["${local.iam_prefix}:role/${var.project}-${each.key}-*", "${local.iam_prefix}:policy/${var.project}-${each.key}-*"]
  }

  statement {
    sid       = "IamReadForPlan"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # The apply role must never be able to change the bootstrap resources or its own permissions.
  statement {
    sid    = "ProtectBootstrap"
    effect = "Deny"
    actions = [
      "iam:Attach*", "iam:Create*", "iam:Delete*", "iam:Detach*", "iam:Put*", "iam:Update*", "iam:PassRole",
    ]
    resources = [
      "${local.iam_prefix}:role/${var.project}-gha-*",
      "${local.iam_prefix}:policy/${var.project}-gha-*",
      "${local.iam_prefix}:role/${var.project}-*-developer",
      "${local.iam_prefix}:role/${var.project}-*-viewer",
      "${local.iam_prefix}:policy/${var.project}-*-viewer",
      aws_iam_openid_connect_provider.github.arn,
    ]
  }

  statement {
    sid       = "ProtectStateBucketConfiguration"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketVersioning"]
    resources = [local.state_bucket]
  }
}

resource "aws_iam_policy" "terraform_apply" {
  for_each = var.environments

  name   = "${var.project}-gha-terraform-apply-${each.key}"
  policy = data.aws_iam_policy_document.terraform_apply[each.key].json
}

resource "aws_iam_role" "terraform_apply" {
  for_each = var.environments

  name                 = "${var.project}-gha-terraform-apply-${each.key}"
  description          = "Applies the ${each.key} platform stack. Only the ${each.key} GitHub environment can assume it."
  assume_role_policy   = data.aws_iam_policy_document.trust_environment[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_apply" {
  for_each = var.environments

  role       = aws_iam_role.terraform_apply[each.key].name
  policy_arn = aws_iam_policy.terraform_apply[each.key].arn
}

# --- dbt deploy: push the image, record its tag, register a task definition revision ---------

data "aws_iam_policy_document" "dbt_deploy" {
  for_each = var.environments

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListTagsForResource",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:${local.partition}:ecr:${var.region}:${local.account_id}:repository/${var.project}-${each.key}-*"]
  }

  statement {
    sid       = "ImageTagParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:ListTagsForResource"]
    resources = ["arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/${var.project}/${each.key}/dbt/*"]
  }

  statement {
    sid       = "SsmDescribe"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # Task definition APIs do not support resource-level permissions.
  statement {
    sid = "TaskDefinition"
    actions = [
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTagsForResource",
      "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadTaskRolesAndLogGroups"
    actions   = ["iam:GetRole", "logs:DescribeLogGroups", "logs:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["${local.iam_prefix}:role/${var.project}-${each.key}-dbt-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.state_bucket]
  }

  statement {
    sid       = "RuntimeStackState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket}/${each.key}/20-dbt-runtime/*"]
  }
}

resource "aws_iam_policy" "dbt_deploy" {
  for_each = var.environments

  name   = "${var.project}-gha-dbt-deploy-${each.key}"
  policy = data.aws_iam_policy_document.dbt_deploy[each.key].json
}

resource "aws_iam_role" "dbt_deploy" {
  for_each = var.environments

  name                 = "${var.project}-gha-dbt-deploy-${each.key}"
  description          = "Publishes the dbt image and rolls the ${each.key} task definition."
  assume_role_policy   = data.aws_iam_policy_document.trust_environment[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "dbt_deploy" {
  for_each = var.environments

  role       = aws_iam_role.dbt_deploy[each.key].name
  policy_arn = aws_iam_policy.dbt_deploy[each.key].arn
}
