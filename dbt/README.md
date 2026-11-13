# dbt

dbt project that turns the raw landing tables into a dimensional model.

```
landing (raw)  ->  staging (views)  ->  intermediate (ephemeral)  ->  marts (tables)
```

| Layer | Rule |
|---|---|
| `staging` | One model per source table: rename, cast, deduplicate. The only place `source()` is used. |
| `intermediate` | Logic shared by several marts. Not exposed to consumers. |
| `marts` | `dim_date`, `dim_customers`, `dim_products`, `fct_orders`, `fct_order_items`. |

## Environments and targets

The project never names an environment. Two settings decide where a run goes:

| Variable | Meaning | Values |
|---|---|---|
| `DBT_ENV` | Which environment's objects to use | `dev`, `tst`, `stg`, `prd` |
| `DBT_TARGET` | How the session authenticates | `local`, `ci`, `runtime` |

`DBT_ENV=stg` means database `STG_ANALYTICS`, raw data from `STG_RAW`, role `STG_TRANSFORMER`.
The `runtime` target writes to the real schemas (`STAGING`, `MARTS`); `local` and `ci` prefix
them (`DBT_<USER>_MARTS`, `PR_42_MARTS`), so only the scheduled job can touch shared tables.

No target uses a password or key: `local` signs in through the browser, `ci` and `runtime` use
workload identity.

## Working locally

```bash
cd dbt
export DBT_PROFILES_DIR=.
export SNOWFLAKE_ACCOUNT=<account identifier>
export SNOWFLAKE_USER=<your user>

uv run dbt deps
uv run dbt build          # models and tests, in your personal schemas
uv run dbt build --select state:modified+ --defer --state <dir with prod manifest>
```

## Tests

- Keys: `unique` and `not_null` on every primary key.
- Relationships: every fact key resolves to its dimension.
- Business rules in `tests/`: an order is paid in full; order lines add up to the order amount.
- Unit test: duplicate and late deliveries of an order collapse to the latest status.
- `dim_customers` has an enforced contract.
