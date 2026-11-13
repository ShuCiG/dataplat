with items as (

    select
        order_id,
        count(*) as line_count,
        sum(quantity) as item_quantity,
        sum(line_amount) as order_amount
    from {{ ref('stg_landing__order_items') }}
    group by order_id

),

payments as (

    select
        order_id,
        sum(iff(payment_status = 'success', amount, 0)) as paid_amount,
        count_if(payment_status = 'failed') as failed_payment_count,
        count_if(payment_status = 'success') as successful_payment_count
    from {{ ref('stg_landing__payments') }}
    group by order_id

)

select
    items.order_id,
    items.line_count,
    items.item_quantity,
    items.order_amount,
    coalesce(payments.paid_amount, 0) as paid_amount,
    coalesce(payments.failed_payment_count, 0) as failed_payment_count,
    coalesce(payments.successful_payment_count, 0) as successful_payment_count
from items
left join payments on items.order_id = payments.order_id
