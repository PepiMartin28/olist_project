with orders_sales as (
    select
        items.orderId as orderId,
        sellers.id as sellerId
    from {{ ref('fact_order_items') }} items
    join {{ ref('dim_sellers') }} sellers
        on items.sellerId = sellers.id
    where items.sellerId is not null
    group by items.orderId, sellers.id
)

select
    items_seller.sellerId as sellerId,
    count(*) as totalOrders,
    countif(isLate) as lateOrders,
    (countif(isLate) * 100.0 / count(*)) as lateRatePct
from {{ ref('fact_orders') }} orders
join orders_sales items_seller
    on orders.id = items_seller.orderId
where orders.isLate is not null
group by items_seller.sellerId
