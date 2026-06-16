select
    sellerId,
    sellerZipCodePrefix,
    sellerCity,
    sellerState
from {{ source('olist_silver', 'sellers_silver') }}