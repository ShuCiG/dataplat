select
    {{ dbt_utils.generate_surrogate_key(['product_id']) }} as product_key,
    product_id,
    product_name,
    category,
    current_price,
    price_valid_from
from {{ ref('stg_landing__products') }}
