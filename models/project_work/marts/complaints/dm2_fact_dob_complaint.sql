-- DM2_FactDOBComplaint
-- Grain: one row per 311 service request routed to DOB (unique_key).
-- Built LAST: ref()s the dimensions so dbt runs them first.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_311_dob') }}
),

dim_date AS (
    SELECT * FROM {{ ref('shared_dim_date') }}
),

dim_geography AS (
    SELECT * FROM {{ ref('shared_dim_geography') }}
),

dim_complaint_type AS (
    SELECT * FROM {{ ref('dm2_dim_complaint_type') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['c.unique_key']) }} AS complaint_key,

    -- Degenerate dimensions / identifiers
    c.unique_key,
    c.bbl,

    -- Foreign keys
    COALESCE(d.date_key, '-1')              AS created_date_key,
    COALESCE(g.geography_key, '-1')         AS geography_key,
    ct.complaint_type_key                   AS complaint_type_key,

    -- Measure
    1                                       AS complaint_count

FROM stg_311 c

LEFT JOIN dim_date d
    ON c.created_date = d.full_date

LEFT JOIN dim_geography g
    ON  c.borough            IS NOT DISTINCT FROM g.borough
    AND c.community_district IS NOT DISTINCT FROM g.community_district
    AND c.zip_code           IS NOT DISTINCT FROM g.zip_code
    AND g.geography_key != '-1'

LEFT JOIN dim_complaint_type ct
    ON  c.complaint_type = ct.complaint_type
    AND c.problem_detail IS NOT DISTINCT FROM ct.problem_detail
