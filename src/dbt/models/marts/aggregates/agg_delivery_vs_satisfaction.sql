with rounded_review_score as (
    select
        coalesce(round(avgReviewScore), -1) as avgReviewScore,
        isLate
    from {{ ref('fact_orders') }}
    where isLate is not null
)

select
    avgReviewScore,
    count(*) as totalOrders,
    countif(isLate) as lateOrders,
    (countif(isLate) * 100.0 / count(*)) as lateRatePct
from rounded_review_score
group by avgReviewScore
order by avgReviewScore