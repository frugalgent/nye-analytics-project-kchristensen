-- Shared_DimDate (conformed): used by dm1_fact_permit and dm2_fact_dob_complaint
-- Grain: one row per calendar date that appears in either source.

WITH stg_permits AS (
    SELECT * FROM {{ ref('stg_dob_permits') }}
),

stg_311 AS (
    SELECT * FROM {{ ref('stg_311_dob') }}
),

all_dates AS (
    -- Permit date roles: issuance_date_key, expiration_date_key
    SELECT DISTINCT issuance_date AS full_date FROM stg_permits WHERE issuance_date IS NOT NULL
    UNION DISTINCT
    SELECT DISTINCT expiration_date FROM stg_permits WHERE expiration_date IS NOT NULL
    UNION DISTINCT
    -- Complaint date role: created_date_key
    SELECT DISTINCT created_date FROM stg_311 WHERE created_date IS NOT NULL
),

date_dimension AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['full_date']) }}               AS date_key,
        full_date,
        EXTRACT(YEAR FROM full_date)                                         AS year,
        EXTRACT(QUARTER FROM full_date)                                      AS quarter,
        CONCAT(CAST(EXTRACT(YEAR FROM full_date) AS STRING), '-Q',
               CAST(EXTRACT(QUARTER FROM full_date) AS STRING))              AS year_quarter,
        EXTRACT(MONTH FROM full_date)                                        AS month,
        FORMAT_DATE('%B', full_date)                                         AS month_name
    FROM all_dates
),

-- Placeholder row: facts point here when a date is missing (e.g. no expiration date)
null_placeholder AS (
    SELECT
        '-1'                    AS date_key,
        CAST(NULL AS DATE)      AS full_date,
        CAST(NULL AS INT64)     AS year,
        CAST(NULL AS INT64)     AS quarter,
        'Unknown'               AS year_quarter,
        CAST(NULL AS INT64)     AS month,
        'Unknown'               AS month_name
)

SELECT * FROM date_dimension
UNION ALL
SELECT * FROM null_placeholder
