select
    customerId as id,
    customerUniqueId as uniqueId,
    customerZipCodePrefix as zipCodePrefix
from {{ ref('stg_customers') }}
