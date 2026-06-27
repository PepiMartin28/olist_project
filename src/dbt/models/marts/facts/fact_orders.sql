with review_score_stg as (
    select
        orderId,
        avg(reviewScore) as avgReviewScore
    from {{ ref('stg_order_reviews') }}
    group by orderId
)

select
    orders.orderId as id,
    orders.customerId,
    orders.orderStatus as fulfillmentStatus,
    reviews.avgReviewScore,
    cast(orders.orderPurchaseTimestamp as date) as purchaseDate,
    timestampdiff(hour, orders.orderPurchaseTimestamp, orders.orderApprovedAt) as processingHours,
    timestampdiff(hour, orders.orderApprovedAt, orders.orderDeliveredCarrierDate) as deliveryHours,
    timestampdiff(hour, orders.orderDeliveredCarrierDate, orders.orderDeliveredCustomerDate) as courierHours,
    timestampdiff(hour, orders.orderPurchaseTimestamp, orders.orderDeliveredCustomerDate) as totalTimeHours,
    timestampdiff(hour, orders.orderPurchaseTimestamp, orders.orderEstimatedDeliveryDate) as estimatedHours,
    timestampdiff(hour, orders.orderEstimatedDeliveryDate, orders.orderDeliveredCustomerDate) as deliveryDelayHours,
    case
        when orders.orderDeliveredCustomerDate is null then null
        when orders.orderDeliveredCustomerDate > orders.orderEstimatedDeliveryDate then true
        else false
    end as isLate
from {{ ref('stg_orders') }} orders
left join review_score_stg reviews
    on orders.orderId = reviews.orderId
