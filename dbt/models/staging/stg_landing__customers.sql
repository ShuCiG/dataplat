with source as (

    select * from {{ source('landing', 'customers') }}

),

latest as (

    select *
    from source
    qualify row_number() over (
        partition by customer_id
        order by updated_at desc, _loaded_at desc
    ) = 1

)

select
    customer_id,
    lower(email) as email,
    first_name,
    last_name,
    upper(country) as country_code,
    created_at,
    updated_at,
    _loaded_at as loaded_at
from latest
