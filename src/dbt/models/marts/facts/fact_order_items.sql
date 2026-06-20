select
    item.orderId as orderId,
    item.orderItemId as orderItemId,
    item.productId as productId,
    item.sellerId as sellerId,
    item.price as price,
    item.freightValue as freightValue
from {{ ref('stg_order_items') }} item