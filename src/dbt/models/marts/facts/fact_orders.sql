with review_score_stg as (
    select
        orderId,
        avg(reviewScore) as avgReviewScore
    from {{ ref('stg_order_reviews') }}
    group by orderId
)

select
    orders.orderId as id,
    orders.customerId as customerId,
    orders.orderStatus as fulfillmentStatus,
    reviews.avgReviewScore as avgReviewScore,
    cast(orders.orderPurchaseTimestamp as date) as purchaseDate,
    timestampdiff(HOUR, orders.orderPurchaseTimestamp, orders.orderApprovedAt) as processingHours,
    timestampdiff(HOUR, orders.orderApprovedAt, orders.orderDeliveredCarrierDate) as deliveryHours,
    timestampdiff(HOUR, orders.orderDeliveredCarrierDate, orders.orderDeliveredCustomerDate) as courierHours,
    timestampdiff(HOUR, orders.orderPurchaseTimestamp, orders.orderDeliveredCustomerDate) as totalTime,
    timestampdiff(HOUR, orders.orderPurchaseTimestamp, orders.orderEstimatedDeliveryDate) as estimatedHours,
    timestampdiff(HOUR, orders.orderEstimatedDeliveryDate, orders.orderDeliveredCustomerDate) as deliveryDelayHours,
    case
        when orders.orderDeliveredCustomerDate is null then null
        when orders.orderDeliveredCustomerDate > orders.orderEstimatedDeliveryDate then true
        else false
    end as isLate
from {{ ref('stg_orders') }} orders
left join review_score_stg reviews
    on orders.orderId = reviews.orderId
