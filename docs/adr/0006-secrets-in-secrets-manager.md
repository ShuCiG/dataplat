# 6. Secrets live in AWS Secrets Manager and are set by hand

Date: 2026-11-13. Status: accepted.

## Context

Most credentials are avoided by design (OIDC for pipelines, workload identity for dbt). A few
cannot be: service users that authenticate with a key pair need their private key stored
somewhere the consumer can read it.

Candidates were GitHub secrets, SSM SecureString parameters and Secrets Manager. GitHub secrets
are only readable from workflows, not from the runtime that needs them. Generating the key in
Terraform would write the private key into state.

## Decision

- Secrets are stored in AWS Secrets Manager, named `dataplat/<env>/<name>`.
- Terraform manages the secret container, its resource policy and the IAM grants. The secret
  value is never an input or output of Terraform.
- A person creates the value and uploads it, following a written procedure in the runbook. The
  procedure includes rotation.
- Plain configuration stays in SSM Parameter Store, which is free and needs no rotation.

## Consequences

- No secret appears in state, plans, logs or the repository.
- Bringing up an environment has manual steps, listed in the runbook, between two applies.
- Secrets Manager charges per secret per month; the count is kept small on purpose.
