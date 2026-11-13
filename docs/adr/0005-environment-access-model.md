# 5. Hands-on access in dev, pipeline-only everywhere else

Date: 2026-11-13. Status: accepted.

## Context

Engineers need a place to experiment without ceremony. Higher environments need the opposite:
every change reviewed, reproducible, and traceable to a commit.

## Decision

- `dev` is a sandbox. People assume `dataplat-dev-developer`, which carries the same policy as
  the `dev` pipeline role, and may change anything in `dev` by hand.
- `tst`, `stg` and `prd` are changed only by GitHub Actions. People get `dataplat-<env>-viewer`,
  which can read resources, logs, lake objects and parameters of that environment and nothing
  else.
- Pipeline roles trust only the GitHub environment of the same name. Environments above `dev`
  accept deployments from `main` only.
- Which environments are sandboxes is a bootstrap variable (`sandbox_environments`), so the model
  is one line to change and visible in review.

## Consequences

- A fix in a higher environment always goes through a pull request, even an urgent one.
- `dev` can drift from its Terraform state after manual changes. The next pipeline run on `main`
  brings it back, which is the intended behaviour for a sandbox.
- The account administrator remains able to bypass this. That identity is for bootstrap and
  recovery, not daily work.
