# Pull request checks for dbt, sandbox only.
#
# A pull request builds the changed models (and what depends on them) into schemas named
# PR_<number>_*, reading raw data from the environment and the models that already exist as the
# baseline to defer to. It can create schemas, so it cannot write into STAGING, INTERMEDIATE or
# MARTS, and it can read, so it never needs a copy of the data.
#
# The user signs in with the GitHub OIDC token of a pull request job. Snowflake accepts one
# subject per user, so this user works for pull requests of this repository and for nothing else.
# Fork pull requests get no token from GitHub at all.

locals {
  ci_enabled = var.sandbox

  # The baseline a pull request defers to: read what dbt built, never write it.
  ci_read_scopes = {
    "all/TABLES"    = { scope = "all", type = "TABLES" }
    "all/VIEWS"     = { scope = "all", type = "VIEWS" }
    "future/TABLES" = { scope = "future", type = "TABLES" }
    "future/VIEWS"  = { scope = "future", type = "VIEWS" }
  }

  ci_read_grants = local.ci_enabled ? merge([
    for schema in keys(snowflake_schema.analytics) : {
      for key, cfg in local.ci_read_scopes : "${schema}/${key}" => merge(cfg, { schema = schema })
    }
  ]...) : {}
}

resource "snowflake_account_role" "ci_access" {
  count = local.ci_enabled ? 1 : 0

  name    = "${local.env}_ANALYTICS_CI"
  comment = "Create pull request schemas in ${local.env}_ANALYTICS and read the models built there."
}

resource "snowflake_account_role" "ci" {
  count = local.ci_enabled ? 1 : 0

  name    = "${local.env}_CI"
  comment = "dbt checks on pull requests: reads RAW, builds PR_<number>_* schemas."
}

resource "snowflake_grant_account_role" "ci_raw_ro" {
  count = local.ci_enabled ? 1 : 0

  role_name        = snowflake_account_role.access["RAW_RO"].name
  parent_role_name = snowflake_account_role.ci[0].name
}

resource "snowflake_grant_account_role" "ci_analytics" {
  count = local.ci_enabled ? 1 : 0

  role_name        = snowflake_account_role.ci_access[0].name
  parent_role_name = snowflake_account_role.ci[0].name
}

resource "snowflake_grant_account_role" "ci_to_sysadmin" {
  count = local.ci_enabled ? 1 : 0

  role_name        = snowflake_account_role.ci[0].name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_privileges_to_account_role" "ci_warehouse" {
  count = local.ci_enabled ? 1 : 0

  account_role_name = snowflake_account_role.ci[0].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.this["TRANSFORMING"].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_database" {
  count = local.ci_enabled ? 1 : 0

  account_role_name = snowflake_account_role.ci_access[0].name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_schema_usage" {
  for_each = local.ci_enabled ? snowflake_schema.analytics : {}

  account_role_name = snowflake_account_role.ci_access[0].name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = each.value.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "ci_read" {
  for_each = local.ci_read_grants

  account_role_name = snowflake_account_role.ci_access[0].name
  privileges        = ["SELECT"]

  on_schema_object {
    dynamic "all" {
      for_each = each.value.scope == "all" ? [1] : []
      content {
        object_type_plural = each.value.type
        in_schema          = snowflake_schema.analytics[each.value.schema].fully_qualified_name
      }
    }

    dynamic "future" {
      for_each = each.value.scope == "future" ? [1] : []
      content {
        object_type_plural = each.value.type
        in_schema          = snowflake_schema.analytics[each.value.schema].fully_qualified_name
      }
    }
  }
}

resource "snowflake_service_user" "ci" {
  count = local.ci_enabled ? 1 : 0

  name              = "${local.env}_DBT_CI_SVC"
  comment           = "dbt checks on pull requests. Authenticates with the GitHub OIDC token of a pull request job."
  default_role      = snowflake_account_role.ci[0].name
  default_warehouse = snowflake_warehouse.this["TRANSFORMING"].name

  default_workload_identity {
    oidc {
      issuer  = "https://token.actions.githubusercontent.com"
      subject = "${var.github_oidc_subject_prefix}:pull_request"
    }
  }

  lifecycle {
    precondition {
      condition     = var.github_oidc_subject_prefix != ""
      error_message = "Set github_oidc_subject_prefix (repo:<owner>/<repo>) so the CI user can be tied to this repository."
    }
  }
}

resource "snowflake_grant_account_role" "ci_user" {
  count = local.ci_enabled ? 1 : 0

  role_name = snowflake_account_role.ci[0].name
  user_name = snowflake_service_user.ci[0].name
}
