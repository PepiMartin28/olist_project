select
    item.orderId,
    item.orderItemId,
    item.productId,
    item.sellerId,
    item.price,
    item.freightValue
from {{ ref('stg_order_items') }} item
