# 9. The dbt image has immutable commit tags, promoted through environments

Date: 2026-11-16. Status: accepted.

## Context

dbt runs from a container image in ECS. A moving tag such as `latest` makes it impossible to say
which code produced a run, and makes rollback a rebuild.

## Decision

- The image is built once per commit and tagged `git-<commit>`. Tags are immutable in ECR.
- The tag in use for an environment is the SSM parameter `/dataplat/<env>/dbt/image_tag`; the
  task definition reads it, so a change takes effect on the next run.
- The same image is promoted dev, tst, stg, prd. Each step gates on `dbt debug --connection`
  running as an ECS task, and stg and prd wait for a human approval.
- Rollback is writing an older tag and re-running the gate.

## Consequences

- What ran in production is always traceable to a commit.
- Rollback needs no build, as long as the old image is within the registry's retention (last 20).
- An environment can lag behind another by design; the promotion run is the only thing that
  moves them.
