with source as (

    select * from {{ source('landing', 'payments') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by payment_id
        order by _loaded_at desc
    ) = 1

)

select
    payment_id,
    order_id,
    method as payment_method,
    status as payment_status,
    amount,
    paid_at,
    _loaded_at as loaded_at
from latest
