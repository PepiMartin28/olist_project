select
    customerId,
    customerUniqueId,
    customerZipCodePrefix,
    customerCity,
    customerState
from {{ source('olist_silver', 'customers_silver') }}
