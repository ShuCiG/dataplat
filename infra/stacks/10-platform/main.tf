locals {
  name_prefix = "${var.project}-${var.environment}"
  dbt_family  = "${local.name_prefix}-dbt"
}

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
}

module "lake" {
  source = "../../modules/s3_lake"

  name_prefix   = local.name_prefix
  force_destroy = var.allow_data_loss
}

module "dbt_image" {
  source = "../../modules/ecr"

  name         = local.dbt_family
  force_delete = var.allow_data_loss
}

module "ecs_dbt" {
  source = "../../modules/ecs_dbt"

  name_prefix              = local.name_prefix
  image_tag_parameter_name = "/${var.project}/${var.environment}/dbt/image_tag"
  lake_bucket_arn          = module.lake.bucket_arn
  log_retention_days       = var.log_retention_days
}

# Everything a workflow needs to know about this environment, in one place. Pipelines read
# this parameter at run time, so their code never names an environment or a resource.
resource "aws_ssm_parameter" "runtime_config" {
  name        = "/${var.project}/${var.environment}/platform/config"
  description = "Runtime configuration of the ${var.environment} platform for workflow code."
  type        = "String"

  value = jsonencode({
    environment         = var.environment
    region              = var.region
    lake_bucket         = module.lake.bucket_name
    ecs_cluster         = module.ecs_dbt.cluster_name
    dbt_task_family     = local.dbt_family
    dbt_container       = "dbt"
    dbt_log_group       = module.ecs_dbt.log_group_name
    dbt_log_prefix      = "dbt"
    task_subnets        = module.network.public_subnet_ids
    task_security_group = module.network.tasks_security_group_id
  })
}

module "orchestrator" {
  source = "../../modules/iam_orchestrator"

  name_prefix        = local.name_prefix
  cluster_arn        = module.ecs_dbt.cluster_arn
  task_family        = local.dbt_family
  passable_role_arns = [module.ecs_dbt.task_role_arn, module.ecs_dbt.execution_role_arn]
  log_group_arn      = module.ecs_dbt.log_group_arn
  lake_bucket_arn    = module.lake.bucket_arn

  readable_parameter_arns = [aws_ssm_parameter.runtime_config.arn]
}
