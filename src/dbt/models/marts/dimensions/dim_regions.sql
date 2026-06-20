select distinct
    {{ dbt_utils.generate_surrogate_key([
        'geolocationCityName',
        'geolocationState'
    ]) }} as id,
    geolocationCityName as city,
    geolocationState as stateName
from {{ ref('stg_geolocation') }}
where geolocationCityName is not null and geolocationState is not null