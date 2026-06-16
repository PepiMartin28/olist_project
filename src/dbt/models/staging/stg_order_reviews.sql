select
    orderId,
    reviewId,
    reviewScore,
    reviewCommentTitle,
    reviewCommentMessage,
    reviewCreationTimestamp,
    reviewAnswerTimestamp
from {{ source('olist_silver', 'order_reviews_silver') }} 