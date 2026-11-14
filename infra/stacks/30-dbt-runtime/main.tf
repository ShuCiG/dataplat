# The dbt task definition, and nothing else. It lives apart from 10-platform because it changes
# on every image deploy: this stack is cheap to plan and is applied by the deploy workflow, which
# has no rights over the rest of the platform.
#
# Everything it needs from the platform is looked up, never created.

locals {
  name_prefix = "${var.project}-${var.environment}"

  # SSM data sources are always sensitive. Both values are plain configuration, not secrets.
  # The platform stack publishes everything workflow code needs to know in one parameter.
  platform = jsondecode(nonsensitive(data.aws_ssm_parameter.platform_config.value))

  image_tag = var.image_tag_override != "" ? var.image_tag_override : nonsensitive(data.aws_ssm_parameter.image_tag.value)
}

data "aws_ssm_parameter" "platform_config" {
  name = "/${var.project}/${var.environment}/platform/config"
}

data "aws_ssm_parameter" "image_tag" {
  name = "/${var.project}/${var.environment}/dbt/image_tag"
}

data "aws_ecr_repository" "dbt" {
  name = local.platform.dbt_task_family
}

data "aws_iam_role" "task" {
  name = "${local.name_prefix}-dbt-task"
}

data "aws_iam_role" "execution" {
  name = "${local.name_prefix}-dbt-task-execution"
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = local.platform.dbt_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  task_role_arn            = data.aws_iam_role.task.arn
  execution_role_arn       = data.aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # dbt writes its target directory and logs to /tmp, so the root filesystem can stay read-only.
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([
    {
      name                   = local.platform.dbt_container
      image                  = "${data.aws_ecr_repository.dbt.repository_url}:${local.image_tag}"
      essential              = true
      readonlyRootFilesystem = true

      # Anything not listed is chosen by whoever starts the task (`command` override).
      command = ["debug"]

      # No credential of any kind: Snowflake accepts the task role itself as proof of identity.
      environment = [
        { name = "DBT_ENV", value = var.environment },
        { name = "DBT_TARGET", value = "runtime" },
        { name = "SNOWFLAKE_ACCOUNT", value = var.snowflake_account },
        { name = "ARTIFACT_BUCKET", value = local.platform.lake_bucket },
      ]

      mountPoints = [
        { sourceVolume = "tmp", containerPath = "/tmp", readOnly = false },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.platform.dbt_log_group
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = local.platform.dbt_log_prefix
        }
      }
    }
  ])
}
