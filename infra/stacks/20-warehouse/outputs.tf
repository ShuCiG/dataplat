output "databases" {
  description = "Databases of the environment."
  value       = { raw = snowflake_database.raw.name, analytics = snowflake_database.analytics.name }
}

output "warehouses" {
  description = "Warehouses by workload."
  value       = { for k, w in snowflake_warehouse.this : lower(k) => w.name }
}

output "landing_stage" {
  description = "Fully qualified name of the landing stage."
  value       = snowflake_stage_external_s3.landing.fully_qualified_name
}

output "service_users" {
  description = "Service users by workload."
  value       = { dbt = snowflake_service_user.dbt.name, airflow = snowflake_service_user.airflow.name }
}

output "people_role" {
  description = "Role to grant to people who work with this environment."
  value       = snowflake_account_role.people.name
}
