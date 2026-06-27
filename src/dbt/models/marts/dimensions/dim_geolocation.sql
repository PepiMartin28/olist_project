with locations as (
    select * from {{ ref('stg_geolocation') }}
),

geo_avg as (
    select
        zipCodePrefix,
        avg(latitude) as latitude,
        avg(longitude) as longitude
    from locations
    group by zipCodePrefix
),

dominant_region as (
    select
        zipCodePrefix,
        regionId
    from (
        select
            loc.zipCodePrefix,
            region.id as regionId,
            count(*) as cnt
        from locations loc
        inner join {{ ref('dim_regions') }} region
            on
                loc.city = region.city
                and loc.stateName = region.stateName
        group by loc.zipCodePrefix, region.id
    )
    qualify row_number() over (
        partition by zipCodePrefix
        order by cnt desc, regionId asc
    ) = 1
)

select
    geo.zipCodePrefix,
    geo.latitude,
    geo.longitude,
    region.regionId
from geo_avg geo
left join dominant_region region
    on geo.zipCodePrefix = region.zipCodePrefix
