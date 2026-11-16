-- DM1_FactPermit
-- Grain: one row per permit action (permit_si_no) issued by DOB.
-- Built LAST: it ref()s every dimension, so dbt runs all dims first (Kimball order).
-- Each LEFT JOIN looks up a dimension's surrogate key; missing values fall back to '-1'.

WITH stg_permits AS (
    SELECT * FROM {{ ref('stg_dob_permits') }}
),

dim_date AS (
    SELECT * FROM {{ ref('shared_dim_date') }}
),

dim_geography AS (
    SELECT * FROM {{ ref('shared_dim_geography') }}
),

dim_permit_type AS (
    SELECT * FROM {{ ref('dm1_dim_permit_type') }}
),

dim_permittee AS (
    SELECT * FROM {{ ref('dm1_dim_permittee') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['p.permit_si_no']) }} AS permit_key,

    -- Degenerate dimensions / identifiers
    p.permit_si_no,
    p.job_number,
    p.bbl,

    -- Foreign keys
    COALESCE(d_iss.date_key, '-1')          AS issuance_date_key,
    COALESCE(g.geography_key, '-1')         AS geography_key,
    pt.permit_type_key                      AS permit_type_key,
    COALESCE(pm.permittee_key, '-1')        AS permittee_key,
    COALESCE(d_exp.date_key, '-1')          AS expiration_date_key,

    -- Measure
    1                                       AS permit_count

FROM stg_permits p

LEFT JOIN dim_date d_iss
    ON p.issuance_date = d_iss.full_date

LEFT JOIN dim_date d_exp
    ON p.expiration_date = d_exp.full_date

-- IS NOT DISTINCT FROM treats NULL = NULL as a match (e.g. a permit with no zip)
LEFT JOIN dim_geography g
    ON  p.borough            IS NOT DISTINCT FROM g.borough
    AND p.community_district IS NOT DISTINCT FROM g.community_district
    AND p.zip_code           IS NOT DISTINCT FROM g.zip_code
    AND g.geography_key != '-1'

LEFT JOIN dim_permit_type pt
    ON  p.job_type      = pt.job_type
    AND p.work_type     IS NOT DISTINCT FROM pt.work_type
    AND p.permit_type   = pt.permit_type
    AND p.filing_status = pt.filing_status
    AND p.permit_status = pt.permit_status

LEFT JOIN dim_permittee pm
    ON  p.license_type   IS NOT DISTINCT FROM pm.license_type
    AND p.license_number = pm.license_number
    AND p.business_name  IS NOT DISTINCT FROM pm.business_name
