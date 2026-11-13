# Production.
environment = "prd"
vpc_cidr    = "10.23.0.0/16"

allow_data_loss    = false
log_retention_days = 90

# People may write to a sandbox directly; everywhere else they only read.
sandbox = false
