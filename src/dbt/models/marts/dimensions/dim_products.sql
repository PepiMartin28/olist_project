select
    product.productId as id,
    category.id as categoryId,
    product.productNameLength as nameLength,
    product.productDescriptionLength as descriptionLength,
    product.productPhotosQty as photosQty,
    product.productWeightG as weightG,
    product.productLengthCm as lengthCm,
    product.productHeightCm as heightCm,
    product.productWidthCm as widthCm
from {{ ref('stg_products') }} product
left join {{ ref('dim_categories') }} category
    on product.productCategoryName <=> category.name
