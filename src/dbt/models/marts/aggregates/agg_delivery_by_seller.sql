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
    {{ delivery_metrics(is_late_column='orders.isLate') }}
from {{ ref('fact_orders') }} orders
join orders_sales items_seller
    on orders.id = items_seller.orderId
where orders.isLate is not null
group by items_seller.sellerId
