with rounded_review_score as (
    select
        coalesce(round(avgReviewScore), -1) as avgReviewScore,
        isLate
    from {{ ref('fact_orders') }}
    where isLate is not null
)

select
    avgReviewScore,
    {{ delivery_metrics(is_late_column='rounded_review_score.isLate') }}
from rounded_review_score
group by avgReviewScore
order by avgReviewScore