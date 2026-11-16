-- Shared_DimGeography (conformed): used by dm1_fact_permit and dm2_fact_dob_complaint
-- Grain: one row per distinct borough / community_district / zip_code combination.
-- Both staging models already store these three columns in the same format.

WITH stg_permits AS (
    SELECT * FROM {{ ref('stg_dob_permits') }}
),

stg_311 AS (
    SELECT * FROM {{ ref('stg_311_dob') }}
),

all_locations AS (
    SELECT DISTINCT borough, community_district, zip_code
    FROM stg_permits
    WHERE borough IS NOT NULL OR community_district IS NOT NULL OR zip_code IS NOT NULL

    UNION DISTINCT

    SELECT DISTINCT borough, community_district, zip_code
    FROM stg_311
    WHERE borough IS NOT NULL OR community_district IS NOT NULL OR zip_code IS NOT NULL
),

geography_dimension AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['borough', 'community_district', 'zip_code']) }} AS geography_key,
        borough,
        community_district,
        zip_code
    FROM all_locations
),

null_placeholder AS (
    SELECT
        '-1'                    AS geography_key,
        'Unknown'               AS borough,
        'Unknown'               AS community_district,
        CAST(NULL AS STRING)    AS zip_code
)

SELECT * FROM geography_dimension
UNION ALL
SELECT * FROM null_placeholder
