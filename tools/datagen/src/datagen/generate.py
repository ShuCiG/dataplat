"""Stateless generation of one day of landing data.

Every value is derived from (seed, date, entity, index), so any day can be produced
on its own and always comes out the same. Nothing depends on earlier runs.

Shape of a daily drop:
  customers    new customers of the day plus changed records of existing ones
  products     full catalogue snapshot; prices move weekly
  orders       orders placed that day plus status changes of orders from the last week
  order_items  lines of the orders placed that day
  payments     payment attempts for the orders placed that day

A small share of order and payment rows is duplicated on purpose.
"""

import random
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pyarrow as pa

from datagen.schemas import SCHEMAS

START_DATE = date(2025, 1, 1)
PRODUCT_COUNT = 200
# Longest possible order lifecycle in days: ship (<=2) + deliver (<=3) + return (<=2).
LIFECYCLE_DAYS = 7
DUPLICATE_RATE = 0.01

_FIRST_NAMES = [
    "Anna", "Ben", "Clara", "David", "Eva", "Felix", "Greta", "Hugo", "Ines", "Jonas",
    "Katja", "Leon", "Mia", "Noah", "Olga", "Paul", "Rosa", "Stefan", "Tina", "Viktor",
]  # fmt: skip
_LAST_NAMES = [
    "Bauer", "Novak", "Fischer", "Kowalski", "Meyer", "Rossi", "Schmidt", "Dubois",
    "Weber", "Jansen", "Wagner", "Silva", "Becker", "Horvat", "Koch", "Lindqvist",
]  # fmt: skip
_COUNTRIES = ["DE", "PL", "FR", "NL", "IT", "ES", "AT", "CZ", "SE", "PT"]
_CATEGORIES = ["electronics", "home", "garden", "toys", "sports", "books", "beauty", "grocery"]
_ADJECTIVES = ["Compact", "Classic", "Premium", "Eco", "Smart", "Travel", "Pro", "Mini"]
_NOUNS = ["Lamp", "Backpack", "Kettle", "Headphones", "Notebook", "Bottle", "Chair", "Speaker"]
_PAYMENT_METHODS = ["card", "paypal", "bank_transfer", "gift_card"]


def _rng(seed: int, *parts: object) -> random.Random:
    # String seeds are hashed with SHA-512, which is stable across platforms and versions.
    return random.Random(":".join(str(p) for p in (seed, *parts)))


def _ts(day: date, second_of_day: int) -> datetime:
    return datetime(day.year, day.month, day.day, tzinfo=UTC) + timedelta(seconds=second_of_day)


def _day_key(day: date) -> int:
    return day.year * 10_000 + day.month * 100 + day.day


def _money(cents: int) -> Decimal:
    return Decimal(cents).scaleb(-2)


def customer_count(seed: int, day: date, scale: float) -> int:
    """Number of customers created on a given day."""
    if day < START_DATE:
        return 0
    return max(1, round(_rng(seed, day, "customer_count").randint(30, 50) * scale))


def order_count(seed: int, day: date, scale: float) -> int:
    """Number of orders placed on a given day. Weekends are busier."""
    if day < START_DATE:
        return 0
    base = _rng(seed, day, "order_count").randint(250, 350)
    weekend = 1.3 if day.weekday() >= 5 else 1.0
    return max(1, round(base * weekend * scale))


def _customer(seed: int, day: date, index: int) -> dict:
    customer_id = _day_key(day) * 10_000 + index
    r = _rng(seed, "customer", customer_id)
    first, last = r.choice(_FIRST_NAMES), r.choice(_LAST_NAMES)
    # Customers sign up in the first six hours so same-day orders always come later.
    created_at = _ts(day, r.randrange(6 * 3600))
    return {
        "customer_id": customer_id,
        "email": f"{first}.{last}.{customer_id}@example.com".lower(),
        "first_name": first,
        "last_name": last,
        "country": r.choice(_COUNTRIES),
        "created_at": created_at,
        "updated_at": created_at,
    }


def _pick_existing_customer(seed: int, day: date, scale: float, r: random.Random) -> dict:
    """Pick a customer created on or before `day`, uniformly over the last year of signups."""
    max_back = min(365, (day - START_DATE).days)
    created_on = day - timedelta(days=r.randint(0, max_back))
    return _customer(seed, created_on, r.randrange(customer_count(seed, created_on, scale)))


def _customers(seed: int, day: date, scale: float) -> list[dict]:
    rows = [_customer(seed, day, i) for i in range(customer_count(seed, day, scale))]
    if day == START_DATE:
        return rows

    r = _rng(seed, day, "customer_updates")
    seen = {row["customer_id"] for row in rows}
    for _ in range(max(1, round(5 * scale))):
        previous_day = day - timedelta(days=1)
        row = _pick_existing_customer(seed, previous_day, scale, r)
        if row["customer_id"] in seen:
            continue
        seen.add(row["customer_id"])
        row["country"] = r.choice(_COUNTRIES)
        row["email"] = f"{row['first_name']}.{row['customer_id']}@example.org".lower()
        row["updated_at"] = _ts(day, r.randrange(86_400))
        rows.append(row)
    return rows


def _price_cents(seed: int, product_id: int, day: date) -> int:
    base = _rng(seed, "product", product_id).randint(300, 25_000)
    week = (day - START_DATE).days // 7
    factor = _rng(seed, "price", product_id, week).uniform(0.9, 1.1)
    return round(base * factor)


def _products(seed: int, day: date) -> list[dict]:
    week_start = START_DATE + timedelta(days=(day - START_DATE).days // 7 * 7)
    rows = []
    for product_id in range(1, PRODUCT_COUNT + 1):
        r = _rng(seed, "product_attrs", product_id)
        rows.append(
            {
                "product_id": product_id,
                "name": f"{r.choice(_ADJECTIVES)} {r.choice(_NOUNS)} {product_id}",
                "category": r.choice(_CATEGORIES),
                "price": _money(_price_cents(seed, product_id, day)),
                "updated_at": _ts(week_start, 0),
            }
        )
    return rows


def _lifecycle(seed: int, order_id: int) -> list[tuple[int, str, int]]:
    """Status changes of an order as (day offset from order day, status, second of day)."""
    r = _rng(seed, "lifecycle", order_id)
    placed_second = r.randrange(6 * 3600, 86_400 - 2)
    events = [(0, "placed", placed_second)]
    if r.random() < 0.05:
        offset = r.randint(0, 1)
        second = r.randrange(placed_second + 1, 86_400) if offset == 0 else r.randrange(86_400)
        events.append((offset, "cancelled", second))
        return events

    shipped = r.randint(1, 2)
    events.append((shipped, "shipped", r.randrange(86_400)))
    delivered = shipped + r.randint(1, 3)
    events.append((delivered, "delivered", r.randrange(86_400)))
    if r.random() < 0.04:
        events.append((delivered + r.randint(1, 2), "returned", r.randrange(86_400)))
    return events


def _order_row(seed: int, order_day: date, index: int, as_of: date, scale: float) -> dict | None:
    """State of an order as delivered in the file of `as_of`, or None if nothing changed then."""
    order_id = _day_key(order_day) * 100_000 + index
    offset = (as_of - order_day).days
    events = _lifecycle(seed, order_id)
    todays = [e for e in events if e[0] == offset]
    if not todays:
        return None

    customer = _pick_existing_customer(seed, order_day, scale, _rng(seed, "order_customer", order_id))
    _, status, second = todays[-1]
    return {
        "order_id": order_id,
        "customer_id": customer["customer_id"],
        "status": status,
        "ordered_at": _ts(order_day, events[0][2]),
        "updated_at": _ts(as_of, second),
    }


def _orders(seed: int, day: date, scale: float) -> list[dict]:
    rows = []
    for back in range(LIFECYCLE_DAYS, -1, -1):
        order_day = day - timedelta(days=back)
        for i in range(order_count(seed, order_day, scale)):
            row = _order_row(seed, order_day, i, day, scale)
            if row is not None:
                rows.append(row)
    return rows


def _items_and_payments(seed: int, day: date, scale: float) -> tuple[list[dict], list[dict]]:
    items: list[dict] = []
    payments: list[dict] = []
    for i in range(order_count(seed, day, scale)):
        order_id = _day_key(day) * 100_000 + i
        r = _rng(seed, "basket", order_id)
        placed_second = _lifecycle(seed, order_id)[0][2]

        total_cents = 0
        product_ids = r.sample(range(1, PRODUCT_COUNT + 1), r.randint(1, 5))
        for line, product_id in enumerate(product_ids, start=1):
            quantity = r.randint(1, 3)
            price_cents = _price_cents(seed, product_id, day)
            total_cents += quantity * price_cents
            items.append(
                {
                    "order_item_id": order_id * 10 + line,
                    "order_id": order_id,
                    "product_id": product_id,
                    "quantity": quantity,
                    "unit_price": _money(price_cents),
                }
            )

        attempts: list[tuple[str, int]] = []
        if r.random() < 0.03:
            attempts.append(("failed", total_cents))
        if r.random() < 0.10 and total_cents > 1:
            first = r.randint(1, total_cents - 1)
            attempts += [("success", first), ("success", total_cents - first)]
        else:
            attempts.append(("success", total_cents))

        for n, (status, cents) in enumerate(attempts, start=1):
            payments.append(
                {
                    "payment_id": order_id * 10 + n,
                    "order_id": order_id,
                    "method": r.choice(_PAYMENT_METHODS),
                    "status": status,
                    "amount": _money(cents),
                    "paid_at": _ts(day, min(placed_second + n, 86_399)),
                }
            )
    return items, payments


def _with_duplicates(rows: list[dict], r: random.Random) -> list[dict]:
    return rows + [dict(row) for row in rows if r.random() < DUPLICATE_RATE]


def generate_day(seed: int, day: date, scale: float = 1.0) -> dict[str, pa.Table]:
    """Build all landing tables for one day."""
    if day < START_DATE:
        raise ValueError(f"date must be on or after {START_DATE.isoformat()}")
    if scale <= 0:
        raise ValueError("scale must be positive")

    items, payments = _items_and_payments(seed, day, scale)
    rows = {
        "customers": _customers(seed, day, scale),
        "products": _products(seed, day),
        "orders": _with_duplicates(_orders(seed, day, scale), _rng(seed, day, "dup_orders")),
        "order_items": items,
        "payments": _with_duplicates(payments, _rng(seed, day, "dup_payments")),
    }
    return {name: pa.Table.from_pylist(rows[name], schema=SCHEMAS[name]) for name in SCHEMAS}
