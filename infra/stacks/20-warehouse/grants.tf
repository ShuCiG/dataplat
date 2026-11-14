# --- RAW_RW: the loader ----------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "raw_rw_database" {
  account_role_name = snowflake_account_role.access["RAW_RW"].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "raw_rw_schema" {
  account_role_name = snowflake_account_role.access["RAW_RW"].name
  privileges        = ["USAGE", "CREATE TABLE"]

  on_schema {
    schema_name = snowflake_schema.landing.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "raw_rw_stage" {
  account_role_name = snowflake_account_role.access["RAW_RW"].name
  privileges        = ["USAGE"]

  on_schema_object {
    object_type = "STAGE"
    object_name = snowflake_stage_external_s3.landing.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "raw_rw_file_format" {
  account_role_name = snowflake_account_role.access["RAW_RW"].name
  privileges        = ["USAGE"]

  on_schema_object {
    object_type = "FILE FORMAT"
    object_name = snowflake_file_format_parquet.landing.fully_qualified_name
  }
}

# --- RAW_RO: readers of raw data -------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "raw_ro_database" {
  account_role_name = snowflake_account_role.access["RAW_RO"].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "raw_ro_schema" {
  account_role_name = snowflake_account_role.access["RAW_RO"].name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = snowflake_schema.landing.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "raw_ro_tables" {
  for_each = toset(["all", "future"])

  account_role_name = snowflake_account_role.access["RAW_RO"].name
  privileges        = ["SELECT"]

  on_schema_object {
    dynamic "all" {
      for_each = each.key == "all" ? [1] : []
      content {
        object_type_plural = "TABLES"
        in_schema          = snowflake_schema.landing.fully_qualified_name
      }
    }

    dynamic "future" {
      for_each = each.key == "future" ? [1] : []
      content {
        object_type_plural = "TABLES"
        in_schema          = snowflake_schema.landing.fully_qualified_name
      }
    }
  }
}

# --- ANALYTICS_RW: dbt -----------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "analytics_rw_database" {
  account_role_name = snowflake_account_role.access["ANALYTICS_RW"].name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analytics_rw_schemas" {
  for_each = snowflake_schema.analytics

  account_role_name = snowflake_account_role.access["ANALYTICS_RW"].name
  all_privileges    = true

  on_schema {
    schema_name = each.value.fully_qualified_name
  }
}

# --- MARTS_RO: consumers ---------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "marts_ro_database" {
  account_role_name = snowflake_account_role.access["MARTS_RO"].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.analytics.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "marts_ro_schema" {
  account_role_name = snowflake_account_role.access["MARTS_RO"].name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = snowflake_schema.analytics["MARTS"].fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "marts_ro_objects" {
  for_each = {
    "all/TABLES"    = { scope = "all", type = "TABLES" }
    "all/VIEWS"     = { scope = "all", type = "VIEWS" }
    "future/TABLES" = { scope = "future", type = "TABLES" }
    "future/VIEWS"  = { scope = "future", type = "VIEWS" }
  }

  account_role_name = snowflake_account_role.access["MARTS_RO"].name
  privileges        = ["SELECT"]

  on_schema_object {
    dynamic "all" {
      for_each = each.value.scope == "all" ? [1] : []
      content {
        object_type_plural = each.value.type
        in_schema          = snowflake_schema.analytics["MARTS"].fully_qualified_name
      }
    }

    dynamic "future" {
      for_each = each.value.scope == "future" ? [1] : []
      content {
        object_type_plural = each.value.type
        in_schema          = snowflake_schema.analytics["MARTS"].fully_qualified_name
      }
    }
  }
}
