from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal

import pytest

from datagen.generate import (
    LIFECYCLE_DAYS,
    START_DATE,
    customer_count,
    generate_day,
)
from datagen.schemas import SCHEMAS

SEED = 7
DAY = date(2025, 3, 15)
SCALE = 0.2


@pytest.fixture(scope="module")
def tables():
    return generate_day(SEED, DAY, SCALE)


def _unique(rows, key):
    return {row[key]: row for row in rows}


def test_all_entities_present_with_declared_schema(tables):
    assert set(tables) == set(SCHEMAS)
    for name, table in tables.items():
        assert table.schema.equals(SCHEMAS[name])
        assert table.num_rows > 0


def test_same_seed_and_date_give_identical_data(tables):
    again = generate_day(SEED, DAY, SCALE)
    for name in SCHEMAS:
        assert tables[name].equals(again[name])


def test_different_seed_gives_different_data(tables):
    other = generate_day(SEED + 1, DAY, SCALE)
    assert not tables["orders"].equals(other["orders"])


def test_day_is_independent_of_other_days(tables):
    generate_day(SEED, DAY - timedelta(days=1), SCALE)
    assert tables["orders"].equals(generate_day(SEED, DAY, SCALE)["orders"])


def test_rejects_dates_before_start_and_bad_scale():
    with pytest.raises(ValueError, match="on or after"):
        generate_day(SEED, START_DATE - timedelta(days=1))
    with pytest.raises(ValueError, match="scale"):
        generate_day(SEED, DAY, 0)


def test_primary_keys_are_unique_where_no_duplicates_are_injected(tables):
    for name, key in [
        ("customers", "customer_id"),
        ("products", "product_id"),
        ("order_items", "order_item_id"),
    ]:
        ids = tables[name].column(key).to_pylist()
        assert len(ids) == len(set(ids)), name


def test_injected_duplicates_are_exact_copies(tables):
    for name, key in [("orders", "order_id"), ("payments", "payment_id")]:
        by_id = defaultdict(list)
        for row in tables[name].to_pylist():
            by_id[row[key]].append(row)
        for rows in by_id.values():
            assert all(row == rows[0] for row in rows)


def test_duplicates_do_occur_at_default_scale():
    orders = generate_day(SEED, DAY)["orders"].column("order_id").to_pylist()
    assert len(orders) > len(set(orders))


def test_successful_payments_equal_order_total(tables):
    item_totals = defaultdict(Decimal)
    for item in tables["order_items"].to_pylist():
        item_totals[item["order_id"]] += item["quantity"] * item["unit_price"]

    paid = defaultdict(Decimal)
    for payment in _unique(tables["payments"].to_pylist(), "payment_id").values():
        if payment["status"] == "success":
            paid[payment["order_id"]] += payment["amount"]

    assert item_totals
    assert paid == item_totals


def test_item_prices_match_catalogue_of_the_day(tables):
    prices = {p["product_id"]: p["price"] for p in tables["products"].to_pylist()}
    for item in tables["order_items"].to_pylist():
        assert item["unit_price"] == prices[item["product_id"]]


def test_new_orders_are_placed_or_cancelled_and_have_items(tables):
    day_prefix = int(DAY.strftime("%Y%m%d"))
    todays = [o for o in tables["orders"].to_pylist() if o["order_id"] // 100_000 == day_prefix]
    assert todays
    assert {o["status"] for o in todays} <= {"placed", "cancelled"}
    assert {o["order_id"] for o in todays} == set(tables["order_items"].column("order_id").to_pylist())


def test_file_carries_status_updates_of_earlier_orders(tables):
    day_prefix = int(DAY.strftime("%Y%m%d"))
    earlier = [o for o in tables["orders"].to_pylist() if o["order_id"] // 100_000 != day_prefix]
    assert earlier
    assert {o["status"] for o in earlier} <= {"cancelled", "shipped", "delivered", "returned"}
    for order in earlier:
        assert order["ordered_at"].date() < DAY
        assert order["updated_at"].date() == DAY
        assert (DAY - order["ordered_at"].date()).days <= LIFECYCLE_DAYS


def test_order_reaches_a_final_status_within_lifecycle_window():
    first = generate_day(SEED, DAY, SCALE)["orders"].to_pylist()
    order_id = next(o["order_id"] for o in first if o["status"] == "placed")

    statuses = ["placed"]
    for n in range(1, LIFECYCLE_DAYS + 1):
        rows = generate_day(SEED, DAY + timedelta(days=n), SCALE)["orders"].to_pylist()
        statuses += [o["status"] for o in _unique(rows, "order_id").values() if o["order_id"] == order_id]

    assert statuses[-1] in {"cancelled", "delivered", "returned"}


def test_orders_reference_customers_that_already_exist(tables):
    for order in tables["orders"].to_pylist():
        created_key, index = divmod(order["customer_id"], 10_000)
        created_on = date(created_key // 10_000, created_key // 100 % 100, created_key % 100)
        assert START_DATE <= created_on <= order["ordered_at"].date()
        assert index < customer_count(SEED, created_on, SCALE)


def test_customer_file_contains_updates_of_existing_customers(tables):
    updated = [c for c in tables["customers"].to_pylist() if c["updated_at"] != c["created_at"]]
    assert updated
    for customer in updated:
        assert customer["created_at"].date() < DAY
        assert customer["updated_at"].date() == DAY
