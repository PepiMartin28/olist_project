select
    sellerId as id,
    sellerZipCodePrefix as zipCodePrefix
from {{ ref('stg_sellers') }}
