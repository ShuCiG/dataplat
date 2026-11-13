# 3. All environments in one AWS account

Date: 2026-11-13. Status: accepted.

## Context

The usual way to isolate environments is one AWS account each, under an organization, with
single sign-on on top. Creating an organization moves the account off the free plan, and the
project has to stay within it.

## Decision

All environments share one account and one region. Isolation is by:

- name prefix `dataplat-<env>-` on every resource
- IAM policies scoped to that prefix: each pipeline role can manage only its own environment
- separate VPCs with non-overlapping ranges
- separate state prefixes, each writable only by the matching apply role

Access for people is by IAM role per environment instead of single sign-on permission sets:
`developer` in `dev`, read-only `viewer` everywhere else.

## Consequences

- Isolation depends on policies being written correctly; an account boundary would not.
- Account-level quotas are shared. Four VPCs plus the default one reach the default limit of
  five per region, so a fifth environment needs a quota increase or the default VPC removed.
- Moving to an account per environment later changes provider configuration and role trust, not
  the stacks themselves.
