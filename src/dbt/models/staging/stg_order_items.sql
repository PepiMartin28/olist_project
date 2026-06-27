select
    orderId,
    orderItemId,
    productId,
    sellerId,
    shippingLimitDate,
    price,
    freightValue
from {{ source('olist_silver', 'order_items_silver') }}
