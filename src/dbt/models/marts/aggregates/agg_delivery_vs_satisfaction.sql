with rounded_review_score as (
    select
        isLate,
        coalesce(round(avgReviewScore), -1) as avgReviewScore
    from {{ ref('fact_orders') }}
    where isLate is not null
)

select
    rounded_review_score.avgReviewScore,
    {{ delivery_metrics(is_late_column='rounded_review_score.isLate') }}
from rounded_review_score
group by rounded_review_score.avgReviewScore
order by rounded_review_score.avgReviewScore
