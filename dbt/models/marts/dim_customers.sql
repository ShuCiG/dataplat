with customers as (

    select * from {{ ref('stg_landing__customers') }}

),

orders as (

    select
        customer_id,
        min(ordered_at) as first_ordered_at,
        max(ordered_at) as last_ordered_at,
        count(*) as lifetime_order_count
    from {{ ref('stg_landing__orders') }}
    group by customer_id

)

select
    {{ dbt_utils.generate_surrogate_key(['customers.customer_id']) }} as customer_key,
    customers.customer_id,
    customers.email,
    customers.first_name,
    customers.last_name,
    customers.country_code,
    customers.created_at as signed_up_at,
    orders.first_ordered_at,
    orders.last_ordered_at,
    coalesce(orders.lifetime_order_count, 0) as lifetime_order_count
from customers
left join orders on customers.customer_id = orders.customer_id
