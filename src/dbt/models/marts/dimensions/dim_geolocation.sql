with geo_avg as (
    select
        geolocationZipCodePrefix as zipCodePrefix,
        avg(geolocationLatitude) as latitude,
        avg(geolocationLongitude) as longitude
    from {{ ref('stg_geolocation') }}
    group by geolocationZipCodePrefix
),

dominant_region as (
    select
        geo.geolocationZipCodePrefix as zipCodePrefix,
        region.id as regionId
    from {{ ref('stg_geolocation') }} as geo
    left join {{ ref('dim_regions') }} as region
        on geo.geolocationCityName = region.city
        and geo.geolocationState  = region.stateName
    group by
        geo.geolocationZipCodePrefix,
        region.id
    qualify row_number() over (
        partition by geo.geolocationZipCodePrefix
        order by count(*) desc, region.id     
    ) = 1
)

select
    a.zipCodePrefix,
    a.latitude,
    a.longitude,
    d.regionId
from geo_avg a
left join dominant_region d
    on a.zipCodePrefix = d.zipCodePrefix