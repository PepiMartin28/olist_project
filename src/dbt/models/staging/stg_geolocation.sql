select
    geolocationZipCodePrefix,
    geolocationLatitude,
    geolocationLongitude,
    geolocationCityName,
    geolocationState
from {{ source('olist_silver', 'geolocation_silver') }} 