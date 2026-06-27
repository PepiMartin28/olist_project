with customer_region as (
    select
        customers.id as customerId,
        coalesce(regions.stateName, 'UNKNOWN') as stateName
    from {{ ref('dim_customers') }} customers
    left join {{ ref('dim_geolocation') }} geo
        on customers.zipCodePrefix = geo.zipCodePrefix
    left join {{ ref('dim_regions') }} regions
        on geo.regionId = regions.id
)

select
    coalesce(customers.stateName, 'UNKNOWN') as stateName,
    {{ delivery_metrics(is_late_column='orders.isLate') }}
from {{ ref('fact_orders') }} orders
left join customer_region customers
    on orders.customerId = customers.customerId
where orders.isLate is not null
group by coalesce(customers.stateName, 'UNKNOWN')
