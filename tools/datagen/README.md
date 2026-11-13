# datagen

Deterministic synthetic e-commerce data generator. Writes daily Parquet partitions and uploads them to the S3 landing zone.

```bash
task datagen -- --date 2025-03-15 --days 3            # tools/datagen/out/landing/...
task datagen:upload -- --date 2025-03-15 --days 3 --bucket <lake-bucket>
```

Layout, identical locally and in the bucket:

```
landing/<entity>/load_date=YYYY-MM-DD/part-0000.parquet
```

## What a daily drop contains

| Entity | Contents |
|---|---|
| `customers` | Customers created that day, plus changed records of existing customers |
| `products` | Full catalogue snapshot. Prices move weekly |
| `orders` | Orders placed that day, plus status changes of orders from the previous 7 days |
| `order_items` | Lines of the orders placed that day |
| `payments` | Payment attempts for the orders placed that day, including failed and split payments |

About 1% of `orders` and `payments` rows are exact duplicates. This is deliberate: downstream models have to deduplicate, and tests have something real to catch.

## Determinism

Every value is derived from `(seed, date, entity, index)`. A day can be generated on its own, in any order, any number of times, and the files are byte-identical. That makes backfills and reloads safe to repeat.

Dates before 2025-01-01 are rejected. `--scale` multiplies volumes (default is roughly 300 orders a day).
