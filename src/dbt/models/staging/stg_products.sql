select
    productId,
    productCategoryName,
    productNameLength,
    productDescriptionLength,
    productPhotosQty,
    productWeightG,
    productLengthCm,
    productHeightCm,
    productWidthCm
from {{ source('olist_silver', 'products_silver') }}
