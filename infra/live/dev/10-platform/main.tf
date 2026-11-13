locals {
  name_prefix = "${var.project}-${var.environment}"
  dbt_family  = "${local.name_prefix}-dbt"
}

module "network" {
  source = "../../../modules/network"

  name_prefix = local.name_prefix
}

module "lake" {
  source = "../../../modules/s3_lake"

  name_prefix   = local.name_prefix
  force_destroy = true # dev data is synthetic and reproducible
}

module "dbt_image" {
  source = "../../../modules/ecr"

  name         = local.dbt_family
  force_delete = true
}

module "ecs_dbt" {
  source = "../../../modules/ecs_dbt"

  name_prefix              = local.name_prefix
  image_tag_parameter_name = "/${var.project}/${var.environment}/dbt/image_tag"
  lake_bucket_arn          = module.lake.bucket_arn
}

module "orchestrator" {
  source = "../../../modules/iam_orchestrator"

  name_prefix        = local.name_prefix
  cluster_arn        = module.ecs_dbt.cluster_arn
  task_family        = local.dbt_family
  passable_role_arns = [module.ecs_dbt.task_role_arn, module.ecs_dbt.execution_role_arn]
  log_group_arn      = module.ecs_dbt.log_group_arn
  lake_bucket_arn    = module.lake.bucket_arn
}
