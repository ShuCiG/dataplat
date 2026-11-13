# 4. Fargate tasks run in public subnets

Date: 2026-11-13. Status: accepted.

## Context

The dbt task needs outbound HTTPS to Snowflake, ECR, S3 and CloudWatch. Nothing ever connects to
it. The standard design puts tasks in private subnets behind a NAT gateway, which costs a fixed
amount per month per environment whether or not anything runs. The task runs for a few minutes a
day.

## Decision

Tasks run in public subnets with a public IP assigned per task. Their security group has no
inbound rules and allows outbound traffic on port 443 only. The VPC default security group is
emptied so it cannot be used by mistake.

## Consequences

- No fixed network cost.
- Task egress addresses are not stable, so the warehouse cannot restrict the service user to a
  known IP range with a network policy. Authentication relies on workload identity alone.
- For a deployment where that restriction is required: private subnets, a NAT gateway with an
  Elastic IP, and a network policy on that address. Only the `network` module changes.
