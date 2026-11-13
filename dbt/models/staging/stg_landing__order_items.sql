with source as (

    select * from {{ source('landing', 'order_items') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by order_item_id
        order by _loaded_at desc
    ) = 1

)

select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    quantity * unit_price as line_amount,
    _loaded_at as loaded_at
from latest
