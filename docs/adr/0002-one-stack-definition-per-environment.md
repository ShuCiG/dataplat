# 2. One stack definition for all environments

Date: 2026-11-13. Status: accepted. Supersedes the initial `infra/live/<env>/` layout.

## Context

The first layout had a directory per environment, each calling the shared modules. Module code was
shared, but the wiring between modules was copied. A change made in `dev` had to be repeated by
hand for every other environment, and nothing guaranteed it was.

With four environments (`dev`, `tst`, `stg`, `prd`) that duplication becomes the main source of
drift.

## Decision

A stack is written once in `infra/stacks/<stack>/`. Environments are instances of it:

- variables come from `infra/envs/<env>.tfvars`
- state is stored under `<env>/<stack>/terraform.tfstate`; the key is passed at `terraform init`

Terraform workspaces were considered and rejected: the active workspace is invisible local state,
which makes it easy to apply to the wrong environment, and a workspace cannot have its own
backend key policy.

## Consequences

- Environments cannot differ in code, only in declared variables.
- A change always rolls through all environments; there is no way to apply it to one only. A
  change that should not reach production yet has to be guarded by a variable.
- Switching environments locally needs `terraform init -reconfigure`.
- Workflows carry an explicit matrix of environments.
