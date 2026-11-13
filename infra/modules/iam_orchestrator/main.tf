# Role assumed by the workflow orchestrator. It can start one task family on one cluster,
# watch it, and check that input files have arrived. It cannot touch warehouse credentials
# or any other AWS resource.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  ecs_arn    = "arn:${local.partition}:ecs:${local.region}:${local.account_id}"

  cluster_name = element(split("/", var.cluster_arn), 1)
}

# Any principal of this account that has been granted sts:AssumeRole on this role may use it.
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-airflow-orchestrator"
  description          = "Starts and monitors dbt tasks, checks landing files."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 43200
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "RunDbtTask"
    actions   = ["ecs:RunTask"]
    resources = ["${local.ecs_arn}:task-definition/${var.task_family}:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }
  }

  statement {
    sid       = "WatchAndStopTasks"
    actions   = ["ecs:DescribeTasks", "ecs:StopTask", "ecs:TagResource"]
    resources = ["${local.ecs_arn}:task/${local.cluster_name}/*"]
  }

  # Describe calls for task definitions do not support resource-level permissions.
  statement {
    sid       = "DescribeTaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions"]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = var.passable_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadTaskLogs"
    actions   = ["logs:GetLogEvents", "logs:DescribeLogStreams", "logs:FilterLogEvents"]
    resources = [var.log_group_arn, "${var.log_group_arn}:*"]
  }

  dynamic "statement" {
    for_each = length(var.readable_parameter_arns) > 0 ? [1] : []

    content {
      sid       = "ReadRuntimeConfig"
      actions   = ["ssm:GetParameter"]
      resources = var.readable_parameter_arns
    }
  }

  statement {
    sid       = "ListLanding"
    actions   = ["s3:ListBucket"]
    resources = [var.lake_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["landing/*"]
    }
  }

  statement {
    sid       = "ReadLanding"
    actions   = ["s3:GetObject"]
    resources = ["${var.lake_bucket_arn}/landing/*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "orchestrate"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
