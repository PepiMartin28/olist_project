select
    customerId as customerId,
    customerUniqueId as customerUniqueId,
    customerZipCodePrefix,
    customerCity,
    customerState
from {{ source('olist_silver', 'customers_silver') }}