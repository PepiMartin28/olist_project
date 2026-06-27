select distinct
    {{ dbt_utils.generate_surrogate_key([
        'productCategoryName'
    ]) }} as id,
    productCategoryName as name
from {{ ref('stg_products') }}
