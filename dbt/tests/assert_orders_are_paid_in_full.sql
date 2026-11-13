-- Every order must be covered exactly by its successful payments.
-- Returns the orders where money and goods do not match.

select
    order_id,
    order_amount,
    paid_amount
from {{ ref('fct_orders') }}
where order_amount != paid_amount
