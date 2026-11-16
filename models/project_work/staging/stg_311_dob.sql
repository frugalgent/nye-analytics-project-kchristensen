-- Staging: NYC 311 service requests routed to DOB
-- Grain: one row per service request (unique_key)
-- Standardizes borough / community district / zip to match stg_dob_permits,
-- cleans BBL, removes rows with no key, date, or complaint type.

WITH source AS (
    SELECT * FROM {{ source('group14_raw', 'source_nyc_311_dob') }}
),

cleaned AS (
    SELECT
        -- Identifiers
        SAFE_CAST(unique_key AS INT64)                  AS unique_key,

        -- Dates
        SAFE_CAST(created_date AS TIMESTAMP)            AS created_at,
        DATE(SAFE_CAST(created_date AS TIMESTAMP))      AS created_date,
        SAFE_CAST(closed_date AS TIMESTAMP)             AS closed_at,

        -- Complaint attributes (-> dm2_dim_complaint_type)
        TRIM(CAST(complaint_type AS STRING))            AS complaint_type,
        NULLIF(TRIM(CAST(descriptor AS STRING)), '')    AS problem_detail,
        UPPER(TRIM(CAST(status AS STRING)))             AS status,

        -- Geography, conformed with stg_dob_permits
        CASE UPPER(TRIM(CAST(borough AS STRING)))
            WHEN 'MANHATTAN'     THEN 'Manhattan'
            WHEN 'BRONX'         THEN 'Bronx'
            WHEN 'BROOKLYN'      THEN 'Brooklyn'
            WHEN 'QUEENS'        THEN 'Queens'
            WHEN 'STATEN ISLAND' THEN 'Staten Island'
            ELSE NULL   -- 'Unspecified' etc.
        END                                             AS borough,

        -- 311 stores community board as text like '11 BROOKLYN'.
        -- Convert to the permit format: borough digit + 2-digit district -> '311'
        CASE
            WHEN REGEXP_CONTAINS(TRIM(CAST(community_board AS STRING)),
                 r'^\d{1,2} (MANHATTAN|BRONX|BROOKLYN|QUEENS|STATEN ISLAND)$')
            THEN CONCAT(
                CASE REGEXP_EXTRACT(TRIM(CAST(community_board AS STRING)), r'^\d{1,2} (.+)$')
                    WHEN 'MANHATTAN' THEN '1' WHEN 'BRONX' THEN '2' WHEN 'BROOKLYN' THEN '3'
                    WHEN 'QUEENS' THEN '4' WHEN 'STATEN ISLAND' THEN '5'
                END,
                LPAD(REGEXP_EXTRACT(TRIM(CAST(community_board AS STRING)), r'^(\d{1,2}) '), 2, '0')
            )
            ELSE NULL   -- e.g. '0 Unspecified'
        END                                             AS community_district,

        CASE
            WHEN REGEXP_CONTAINS(TRIM(CAST(incident_zip AS STRING)), r'^\d{5}')
            THEN LEFT(TRIM(CAST(incident_zip AS STRING)), 5)
            ELSE NULL
        END                                             AS zip_code,

        -- BBL: strip any trailing '.0' from numeric loads; keep only valid 10-digit values
        CASE
            WHEN REGEXP_CONTAINS(REGEXP_REPLACE(CAST(bbl AS STRING), r'\.0+$', ''), r'^[1-5]\d{9}$')
            THEN REGEXP_REPLACE(CAST(bbl AS STRING), r'\.0+$', '')
            ELSE NULL
        END                                             AS bbl,

        CAST(incident_address AS STRING)                AS incident_address,
        CAST(open_data_channel_type AS STRING)          AS method_of_submission,

        CURRENT_TIMESTAMP()                             AS _stg_loaded_at

    FROM source
    WHERE agency = 'DOB'
)

SELECT *
FROM cleaned
WHERE unique_key IS NOT NULL
  AND created_date IS NOT NULL
  AND complaint_type IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY unique_key ORDER BY created_at DESC) = 1