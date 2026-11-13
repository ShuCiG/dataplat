"""Arrow schemas of the landing files. These are the contract with the warehouse loader."""

import pyarrow as pa

_TS = pa.timestamp("us", tz="UTC")
_MONEY = pa.decimal128(12, 2)

CUSTOMERS = pa.schema(
    [
        pa.field("customer_id", pa.int64(), nullable=False),
        pa.field("email", pa.string(), nullable=False),
        pa.field("first_name", pa.string(), nullable=False),
        pa.field("last_name", pa.string(), nullable=False),
        pa.field("country", pa.string(), nullable=False),
        pa.field("created_at", _TS, nullable=False),
        pa.field("updated_at", _TS, nullable=False),
    ]
)

PRODUCTS = pa.schema(
    [
        pa.field("product_id", pa.int64(), nullable=False),
        pa.field("name", pa.string(), nullable=False),
        pa.field("category", pa.string(), nullable=False),
        pa.field("price", _MONEY, nullable=False),
        pa.field("updated_at", _TS, nullable=False),
    ]
)

ORDERS = pa.schema(
    [
        pa.field("order_id", pa.int64(), nullable=False),
        pa.field("customer_id", pa.int64(), nullable=False),
        pa.field("status", pa.string(), nullable=False),
        pa.field("ordered_at", _TS, nullable=False),
        pa.field("updated_at", _TS, nullable=False),
    ]
)

ORDER_ITEMS = pa.schema(
    [
        pa.field("order_item_id", pa.int64(), nullable=False),
        pa.field("order_id", pa.int64(), nullable=False),
        pa.field("product_id", pa.int64(), nullable=False),
        pa.field("quantity", pa.int32(), nullable=False),
        pa.field("unit_price", _MONEY, nullable=False),
    ]
)

PAYMENTS = pa.schema(
    [
        pa.field("payment_id", pa.int64(), nullable=False),
        pa.field("order_id", pa.int64(), nullable=False),
        pa.field("method", pa.string(), nullable=False),
        pa.field("status", pa.string(), nullable=False),
        pa.field("amount", _MONEY, nullable=False),
        pa.field("paid_at", _TS, nullable=False),
    ]
)

SCHEMAS: dict[str, pa.Schema] = {
    "customers": CUSTOMERS,
    "products": PRODUCTS,
    "orders": ORDERS,
    "order_items": ORDER_ITEMS,
    "payments": PAYMENTS,
}
