with customer_region as (
    select
        customers.id as customerId,
        regions.stateName as stateName
    from {{ ref('dim_customers') }} customers
    join {{ ref('dim_geolocation') }} geo
        on customers.zipCodePrefix = geo.zipCodePrefix
    join {{ ref('dim_regions') }} regions
        on geo.regionId = regions.id
    where customers.zipCodePrefix is not null
)   

select
    customers.stateName as stateName,
    count(*) as totalOrders,
    countif(isLate) as lateOrders,
    (countif(isLate) * 100.0 / count(*)) as lateRatePct
from {{ ref('fact_orders') }} orders
join customer_region customers
    on orders.customerId = customers.id
where orders.isLate is not null
group by customers.stateName
