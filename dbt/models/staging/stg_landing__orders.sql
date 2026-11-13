with source as (

    select * from {{ source('landing', 'orders') }}

),

-- One row per order: the most recent status wins. This also removes exact duplicates.
latest as (

    select *
    from source
    qualify row_number() over (
        partition by order_id
        order by updated_at desc, _loaded_at desc
    ) = 1

)

select
    order_id,
    customer_id,
    status as order_status,
    ordered_at,
    updated_at as status_updated_at,
    _loaded_at as loaded_at
from latest
