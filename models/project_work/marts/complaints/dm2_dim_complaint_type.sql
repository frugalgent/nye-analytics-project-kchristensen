-- DM2_DimComplaintType (complaints mart only)
-- Grain: one row per distinct complaint_type / problem_detail (311 descriptor).
-- is_permit_related is DERIVED: flags complaints that allege missing or violated permits,
-- which is what our "complaints at buildings without an active permit" metric needs.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_311_dob') }}
),

distinct_complaint_types AS (
    SELECT DISTINCT
        complaint_type,
        problem_detail
    FROM stg_311
),

enriched AS (
    SELECT
        complaint_type,
        problem_detail,
        CASE
            -- '%' wildcards used around dashes because the source mixes '-' and other dash characters
            WHEN LOWER(problem_detail) LIKE '%building permit%none%'           THEN TRUE
            WHEN LOWER(problem_detail) LIKE '%work without a permit%'          THEN TRUE
            WHEN LOWER(problem_detail) LIKE '%contrary%beyond approved%'       THEN TRUE
            WHEN LOWER(problem_detail) LIKE '%after hours work%'               THEN TRUE
            WHEN LOWER(problem_detail) LIKE '%stop work order%'                THEN TRUE
            ELSE FALSE
        END AS is_permit_related
    FROM distinct_complaint_types
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['complaint_type', 'problem_detail']) }} AS complaint_type_key,
    complaint_type,
    problem_detail,
    is_permit_related
FROM enriched
