# 8. Services sign in to Snowflake with workload identity, not keys

Date: 2026-11-16. Status: accepted.

## Context

The first plan used a key pair for the Airflow service user, because a laptop has no stable AWS
identity. In practice Airflow assumes an AWS role (`dataplat-<env>-airflow-orchestrator`) through
a local profile, and that role can be presented to Snowflake the same way the ECS task role is.
Terraform does the same with a role of its own.

## Decision

Every service user (`<ENV>_DBT_SVC`, `<ENV>_AIRFLOW_SVC`, `TERRAFORM_<ENV>`) authenticates with
Snowflake workload identity of type AWS, bound to one IAM role. No passwords and no private keys
exist for them. Key-pair users are only created when workload identity cannot work, with the
secret handling from [ADR 6](0006-secrets-in-secrets-manager.md).

## Consequences

- Nothing to rotate or leak for these users; access is revoked by changing the role's trust or
  the user's identity binding.
- A user is tied to one role ARN. A new machine or runner works only if it can assume that role.
- A person who needs a Snowflake session as a service user must first assume the matching AWS
  role; the runbook lists the profiles.
