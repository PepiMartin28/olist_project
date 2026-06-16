select
    orderId,
    paymentSequential,
    paymentType,
    paymentInstallments,
    paymentValue
from {{ source('olist_silver', 'order_payments_silver') }} 