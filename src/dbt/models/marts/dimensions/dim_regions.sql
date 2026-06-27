select distinct
    {{ dbt_utils.generate_surrogate_key([
        'city',
        'stateName'
    ]) }} as id,
    city,
    stateName
from {{ ref('stg_geolocation') }}
where city is not null and stateName is not null