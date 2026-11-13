# Two layers of roles.
#
#   access roles      hold privileges on objects and nothing else     <ENV>_RAW_RW ...
#   functional roles  bundle access roles for a job to be done        <ENV>_LOADER ...
#
# Users are only ever granted functional roles, and privileges are only ever granted to
# access roles, so "who can do what" is answered by reading this one file.

locals {
  access_roles = {
    RAW_RW       = "Create and load tables in ${local.env}_RAW.LANDING."
    RAW_RO       = "Read ${local.env}_RAW."
    ANALYTICS_RW = "Build models in ${local.env}_ANALYTICS."
    MARTS_RO     = "Read ${local.env}_ANALYTICS.MARTS."
  }

  functional_roles = {
    LOADER      = { comment = "Loads landing files into RAW.", access = ["RAW_RW"], warehouse = "LOADING" }
    TRANSFORMER = { comment = "Runs dbt: reads RAW, builds ANALYTICS.", access = ["RAW_RO", "ANALYTICS_RW"], warehouse = "TRANSFORMING" }
    ANALYST     = { comment = "Reads the marts.", access = ["MARTS_RO"], warehouse = "REPORTING" }
  }

  functional_access = merge([
    for role, cfg in local.functional_roles : {
      for access in cfg.access : "${role}/${access}" => { role = role, access = access }
    }
  ]...)

  # What a person gets in this environment: everything in a sandbox, read-only elsewhere.
  people_role = var.sandbox ? "DEVELOPER" : "VIEWER"
  people_gets = var.sandbox ? ["LOADER", "TRANSFORMER", "ANALYST"] : ["ANALYST"]
}

resource "snowflake_account_role" "access" {
  for_each = local.access_roles

  name    = "${local.env}_${each.key}"
  comment = each.value
}

resource "snowflake_account_role" "functional" {
  for_each = local.functional_roles

  name    = "${local.env}_${each.key}"
  comment = each.value.comment
}

resource "snowflake_grant_account_role" "functional_access" {
  for_each = local.functional_access

  role_name        = snowflake_account_role.access[each.value.access].name
  parent_role_name = snowflake_account_role.functional[each.value.role].name
}

# Custom roles roll up to SYSADMIN so administrators keep sight of every object.
resource "snowflake_grant_account_role" "functional_to_sysadmin" {
  for_each = local.functional_roles

  role_name        = snowflake_account_role.functional[each.key].name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  for_each = local.functional_roles

  account_role_name = snowflake_account_role.functional[each.key].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.this[each.value.warehouse].name
  }
}

# --- role for people -------------------------------------------------------------------------
# Granted to individual users by hand, see docs/runbook.md.

resource "snowflake_account_role" "people" {
  name    = "${local.env}_${local.people_role}"
  comment = var.sandbox ? "Hands-on access to ${local.env}: load, transform and read." : "Read-only access to ${local.env}. Changes go through the pipeline."
}

resource "snowflake_grant_account_role" "people" {
  for_each = toset(local.people_gets)

  role_name        = snowflake_account_role.functional[each.key].name
  parent_role_name = snowflake_account_role.people.name
}

resource "snowflake_grant_account_role" "people_to_sysadmin" {
  role_name        = snowflake_account_role.people.name
  parent_role_name = "SYSADMIN"
}
