with locations as (
    select
        geolocationZipCodePrefix as zipCodePrefix,
        geolocationCityName as city,
        geolocationState as stateName,
        geolocationLatitude as latitude,
        geolocationLongitude as longitude
    from {{ source('olist_silver', 'geolocation_silver') }}

    union all

    select
        sellerZipCodePrefix as zipCodePrefix,
        sellerCity as city,
        sellerState as stateName,
        cast(null as double) as latitude,
        cast(null as double) as longitude
    from {{ source('olist_silver', 'sellers_silver') }}

    union all

    select
        customerZipCodePrefix as zipCodePrefix,
        customerCity as city,
        customerState as stateName,
        cast(null as double) as latitude,
        cast(null as double) as longitude
    from {{ source('olist_silver', 'customers_silver') }}
)

select * from locations
