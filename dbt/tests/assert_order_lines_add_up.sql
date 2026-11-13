-- The incremental line fact must stay consistent with the order fact.

with lines as (

    select
        order_id,
        sum(line_amount) as line_total
    from {{ ref('fct_order_items') }}
    group by order_id

)

select
    orders.order_id,
    orders.order_amount,
    lines.line_total
from {{ ref('fct_orders') }} as orders
inner join lines on orders.order_id = lines.order_id
where orders.order_amount != lines.line_total
