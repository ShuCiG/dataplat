# 10. Pull requests build changed dbt models in dev, under their own schemas

Date: 2026-11-16. Status: accepted.

## Context

Parsing the dbt project catches broken references but not broken SQL or failing tests. Running
the changed models against real data before merge catches both. A pull request must not be able to
damage what the scheduled job owns, and a public repository must not hand warehouse access to
people who only opened a pull request.

## Decision

- A workflow (`dbt-ci`) builds `state:modified+` with `--defer`, against the manifest of the last
  dbt run in dev. Unchanged models are read from dev's schemas instead of being rebuilt.
- Everything lands in `PR_<number>_*` schemas of `DEV_ANALYTICS`. `generate_schema_name` already
  prefixes schemas this way for every target except `runtime`. A second workflow
  (`dbt-ci-cleanup`) drops them when the pull request closes.
- The job signs in as `DEV_DBT_CI_SVC` with the GitHub OIDC token of a pull request job. The user
  accepts exactly one subject, `<repository>:pull_request`. Its role `DEV_CI` can read `DEV_RAW`,
  create schemas in `DEV_ANALYTICS` and read what is in them. It cannot write to `STAGING`,
  `INTERMEDIATE` or `MARTS`.
- Only dev has this user (sandbox). The other environments are reached by promotion only.
- Fork and Dependabot pull requests are skipped: GitHub gives them no token.

## Consequences

- A pull request can run SQL in dev with the permissions above, so write access to the repository
  is trusted to that extent. Reviewing a workflow or macro change deserves the same care as
  reviewing infrastructure.
- The baseline is whatever the last dbt run in dev built. If dev is behind `main`, more models
  count as modified; if dev has never run, the job fails until it has.
- Schemas of a pull request that was never closed through GitHub stay until someone drops them
  with `dbt run-operation drop_pr_schemas`.
