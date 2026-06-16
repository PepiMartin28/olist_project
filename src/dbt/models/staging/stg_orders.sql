select
    orderId,
    customerId,
    orderStatus,
    orderPurchaseTimestamp,
    orderApprovedAt,
    orderDeliveredCarrierDate,
    orderDeliveredCustomerDate,
    orderEstimatedDeliveryDate
from {{ source('olist_silver', 'orders_silver') }}