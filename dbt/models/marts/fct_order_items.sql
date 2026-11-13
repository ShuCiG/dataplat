{{
    config(
        materialized='incremental',
        unique_key='order_item_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

with items as (

    select * from {{ ref('stg_landing__order_items') }}

    {% if is_incremental() %}
        -- Lines are immutable; only rows loaded since the last run need processing.
        where loaded_at > (select coalesce(max(loaded_at), '1900-01-01') from {{ this }})
    {% endif %}

),

orders as (

    select
        order_id,
        customer_id,
        ordered_at
    from {{ ref('stg_landing__orders') }}

)

select
    items.order_item_id,
    items.order_id,
    {{ dbt_utils.generate_surrogate_key(['items.product_id']) }} as product_key,
    {{ dbt_utils.generate_surrogate_key(['orders.customer_id']) }} as customer_key,
    to_number(to_char(orders.ordered_at, 'YYYYMMDD')) as order_date_key,
    items.quantity,
    items.unit_price,
    items.line_amount,
    items.loaded_at
from items
inner join orders on items.order_id = orders.order_id
