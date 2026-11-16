-- DM1_DimPermittee (permits mart only)
-- Grain: one row per distinct license_type / license_number / business_name.

WITH stg_permits AS (
    SELECT * FROM {{ ref('stg_dob_permits') }}
),

distinct_permittees AS (
    SELECT DISTINCT
        license_type,
        license_number,
        business_name
    FROM stg_permits
    WHERE license_number IS NOT NULL
),

permittee_dimension AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['license_type', 'license_number', 'business_name']) }}
            AS permittee_key,
        license_type,
        license_number,
        business_name
    FROM distinct_permittees
),

-- Some permits have no permittee license recorded
null_placeholder AS (
    SELECT
        '-1'                    AS permittee_key,
        'Unknown'               AS license_type,
        'Unknown'               AS license_number,
        CAST(NULL AS STRING)    AS business_name
)

SELECT * FROM permittee_dimension
UNION ALL
SELECT * FROM null_placeholder
