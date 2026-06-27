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
    select zipCodePrefix, regionId
    from (
        select
            loc.zipCodePrefix as zipCodePrefix,
            region.id as regionId,
            count(*) as cnt
        from locations as loc
        join {{ ref('dim_regions') }} as region
            on loc.city = region.city
            and loc.stateName = region.stateName
        group by loc.zipCodePrefix, region.id
    )
    qualify row_number() over (
        partition by zipCodePrefix
        order by cnt desc, regionId
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