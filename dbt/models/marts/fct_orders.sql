with orders as (

    select * from {{ ref('stg_landing__orders') }}

),

amounts as (

    select * from {{ ref('int_orders__amounts') }}

)

select
    orders.order_id,
    {{ dbt_utils.generate_surrogate_key(['orders.customer_id']) }} as customer_key,
    to_number(to_char(orders.ordered_at, 'YYYYMMDD')) as order_date_key,
    orders.order_status,
    orders.ordered_at,
    orders.status_updated_at,
    coalesce(amounts.line_count, 0) as line_count,
    coalesce(amounts.item_quantity, 0) as item_quantity,
    coalesce(amounts.order_amount, 0) as order_amount,
    coalesce(amounts.paid_amount, 0) as paid_amount,
    coalesce(amounts.failed_payment_count, 0) as failed_payment_count,
    coalesce(amounts.successful_payment_count, 0) > 1 as is_split_payment,
    orders.order_status in ('cancelled', 'returned') as is_lost_sale
from orders
left join amounts on orders.order_id = amounts.order_id
