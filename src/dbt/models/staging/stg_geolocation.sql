with all_zipCodes as (
    select
        geolocationZipCodePrefix as zipCodePrefix,
        geolocationCityName as city,
        geolocationState as stateName
    from {{ source('olist_silver', 'geolocation_silver') }} 
    
    union
    
    select
        sellerZipCodePrefix as zipCodePrefix,
        sellerCity as city,
        sellerState as stateName
    from {{ source('olist_silver', 'sellers_silver') }}
    
    union

    select
        customerZipCodePrefix as zipCodePrefix,
        customerCity as city,
        customerState as stateName
    from {{ source('olist_silver', 'customers_silver') }}
)

select distinct
    zip.zipCodePrefix as geolocationZipCodePrefix,
    geo.geolocationLatitude as geolocationLatitude,
    geo.geolocationLongitude as geolocationLongitude,
    zip.city as geolocationCityName,
    zip.stateName as geolocationState
from all_zipCodes zip
left join {{ source('olist_silver', 'geolocation_silver') }} geo
    on 
        zip.zipCodePrefix = geo.geolocationZipCodePrefix 
        and zip.city = geo.geolocationCityName 
        and zip.stateName = geo.geolocationState