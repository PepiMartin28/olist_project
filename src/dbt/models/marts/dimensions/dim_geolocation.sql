with locations as (
    select * from {{ ref('stg_geolocation') }}
),

geo_avg as (
    select
        zipCodePrefix,
        avg(latitude)  as latitude,
        avg(longitude) as longitude
    from locations
    group by zipCodePrefix
),

dominant_region as (
    select
        loc.zipCodePrefix,
        region.id as regionId
    from locations as loc
    join {{ ref('dim_regions') }} as region
        on loc.city = region.city
        and loc.stateName = region.stateName
    group by loc.zipCodePrefix, region.id
    qualify row_number() over (
        partition by loc.zipCodePrefix
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