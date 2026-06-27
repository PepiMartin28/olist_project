-- Every delivered order must be counted exactly once across customer regions.
-- Fails (returns rows) if agg_delivery_by_customer_region silently drops orders
-- whose customer zip does not resolve to a region, or double-counts them.
with delivered as (
    select count(*) as n
    from {{ ref('fact_orders') }}
    where isLate is not null
),

aggregated as (
    select sum(totalOrders) as n
    from {{ ref('agg_delivery_by_customer_region') }}
)

select
    delivered.n as delivered_orders,
    aggregated.n as aggregated_orders
from delivered
cross join aggregated
where delivered.n <> aggregated.n
