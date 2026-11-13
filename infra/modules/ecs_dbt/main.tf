# Everything the dbt task needs except the task definition itself, which lives in its own
# stack because it changes on every image deploy.

resource "aws_ecs_cluster" "this" {
  name = var.name_prefix

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "dbt" {
  name              = "/ecs/${var.name_prefix}/dbt"
  retention_in_days = var.log_retention_days
}

# The deploy pipeline owns the value. Terraform only creates the parameter.
resource "aws_ssm_parameter" "image_tag" {
  name        = var.image_tag_parameter_name
  description = "Tag of the dbt image the task definition should run."
  type        = "String"
  value       = "bootstrap"

  lifecycle {
    ignore_changes = [value]
  }
}

data "aws_iam_policy_document" "assume_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Execution role: used by the ECS agent to pull the image and ship logs.
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-dbt-task-execution"
  description        = "Lets ECS pull the dbt image and write its logs."
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: the identity of the running container. Its ARN is also what the warehouse
# trusts for workload identity authentication, so it must stay stable.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-dbt-task"
  description        = "Identity of the running dbt container."
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "WriteRunArtifacts"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${var.lake_bucket_arn}/artifacts/dbt/*"]
  }

  statement {
    sid       = "ListRunArtifacts"
    actions   = ["s3:ListBucket"]
    resources = [var.lake_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["artifacts/dbt/*"]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "artifacts"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
