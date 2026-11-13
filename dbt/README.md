# dbt

dbt project and the container image that runs it on ECS Fargate.

Layers: `staging` (views, one per source table) -> `intermediate` -> `marts` (dimensions and facts).
