# Service users. Each one is tied to the AWS role of the workload that uses it and can only
# be used from that role: no passwords, no keys, nothing to rotate or leak.

resource "snowflake_service_user" "dbt" {
  name              = "${local.env}_DBT_SVC"
  comment           = "dbt on ECS. Authenticates as the dbt task role."
  default_role      = snowflake_account_role.functional["TRANSFORMER"].name
  default_warehouse = snowflake_warehouse.this["TRANSFORMING"].name

  default_workload_identity {
    aws {
      arn = data.aws_iam_role.dbt_task.arn
    }
  }
}

resource "snowflake_grant_account_role" "dbt" {
  role_name = snowflake_account_role.functional["TRANSFORMER"].name
  user_name = snowflake_service_user.dbt.name
}

resource "snowflake_service_user" "airflow" {
  name              = "${local.env}_AIRFLOW_SVC"
  comment           = "Orchestrator: loads landing files. Authenticates as the orchestrator role."
  default_role      = snowflake_account_role.functional["LOADER"].name
  default_warehouse = snowflake_warehouse.this["LOADING"].name

  default_workload_identity {
    aws {
      arn = data.aws_iam_role.orchestrator.arn
    }
  }
}

resource "snowflake_grant_account_role" "airflow" {
  role_name = snowflake_account_role.functional["LOADER"].name
  user_name = snowflake_service_user.airflow.name
}
