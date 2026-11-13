with source as (

    select * from {{ source('landing', 'products') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by product_id
        order by updated_at desc, _loaded_at desc
    ) = 1

)

select
    product_id,
    name as product_name,
    category,
    price as current_price,
    updated_at as price_valid_from,
    _loaded_at as loaded_at
from latest
