-- Staging: DOB Permit Issuance
-- Grain: one row per permit action (permit_si_no)
-- Cleans text dates, standardizes borough / community district / zip so they
-- conform with the 311 staging table, builds BBL, removes never-issued permits.
--
-- Column names below are the NYC Open Data API field names (e.g. job__, permittee_s_license__).
-- If dbt says a column is not found, check the Schema tab of the raw table in BigQuery.

WITH source AS (
    SELECT * FROM {{ source('group14_raw', 'source_nyc_dob_permits') }}
),

cleaned AS (
    SELECT
        -- Identifiers
        CAST(permit_si_no AS STRING)                    AS permit_si_no,
        CAST(job__ AS STRING)                           AS job_number,
        CAST(job_doc___ AS STRING)                      AS job_doc_number,

        -- Permit type attributes (-> dm1_dim_permit_type)
        UPPER(TRIM(CAST(job_type AS STRING)))           AS job_type,
        NULLIF(UPPER(TRIM(CAST(work_type AS STRING))), '') AS work_type,
        UPPER(TRIM(CAST(permit_type AS STRING)))        AS permit_type,
        UPPER(TRIM(CAST(filing_status AS STRING)))      AS filing_status,
        UPPER(TRIM(CAST(permit_status AS STRING)))      AS permit_status,

        -- Permittee attributes (-> dm1_dim_permittee)
        NULLIF(UPPER(TRIM(CAST(permittee_s_license_type AS STRING))), '')  AS license_type,
        NULLIF(TRIM(CAST(permittee_s_license__ AS STRING)), '')            AS license_number,
        NULLIF(UPPER(TRIM(CAST(permittee_s_business_name AS STRING))), '') AS business_name,

        -- Dates (stored as text in the source)
        {{ parse_dob_date('filing_date') }}             AS filing_date,
        {{ parse_dob_date('issuance_date') }}           AS issuance_date,
        {{ parse_dob_date('expiration_date') }}         AS expiration_date,

        -- Geography, conformed with stg_311_dob
        CASE UPPER(TRIM(CAST(borough AS STRING)))
            WHEN 'MANHATTAN'     THEN 'Manhattan'
            WHEN 'BRONX'         THEN 'Bronx'
            WHEN 'BROOKLYN'      THEN 'Brooklyn'
            WHEN 'QUEENS'        THEN 'Queens'
            WHEN 'STATEN ISLAND' THEN 'Staten Island'
            ELSE NULL
        END                                             AS borough,

        -- Community district as 3-digit code: borough digit + 2-digit district (e.g. '311')
        CASE
            WHEN REGEXP_CONTAINS(TRIM(CAST(community_board AS STRING)), r'^[1-5]\d{2}$')
            THEN TRIM(CAST(community_board AS STRING))
            ELSE NULL
        END                                             AS community_district,

        CASE
            WHEN REGEXP_CONTAINS(TRIM(CAST(zip_code AS STRING)), r'^\d{5}')
            THEN LEFT(TRIM(CAST(zip_code AS STRING)), 5)
            ELSE NULL
        END                                             AS zip_code,

        -- BBL = borough code (1) + block (5, zero-padded) + lot (4, zero-padded)
        CASE
            WHEN SAFE_CAST(block AS INT64) IS NOT NULL AND SAFE_CAST(lot AS INT64) IS NOT NULL
             AND UPPER(TRIM(CAST(borough AS STRING))) IN ('MANHATTAN','BRONX','BROOKLYN','QUEENS','STATEN ISLAND')
            THEN CONCAT(
                CASE UPPER(TRIM(CAST(borough AS STRING)))
                    WHEN 'MANHATTAN' THEN '1' WHEN 'BRONX' THEN '2' WHEN 'BROOKLYN' THEN '3'
                    WHEN 'QUEENS' THEN '4' WHEN 'STATEN ISLAND' THEN '5'
                END,
                LPAD(CAST(SAFE_CAST(block AS INT64) AS STRING), 5, '0'),
                LPAD(CAST(SAFE_CAST(lot AS INT64) AS STRING), 4, '0')
            )
            ELSE NULL
        END                                             AS bbl,

        CURRENT_TIMESTAMP()                             AS _stg_loaded_at

    FROM source
    WHERE permit_si_no IS NOT NULL
)

SELECT *
FROM cleaned
-- Only permits that were actually issued (about 21K rows have no issuance date)
WHERE issuance_date IS NOT NULL
  AND job_type IS NOT NULL
  AND permit_type IS NOT NULL
  AND filing_status IS NOT NULL
  AND permit_status IS NOT NULL
-- Deduplicate: keep the latest issuance per permit_si_no
QUALIFY ROW_NUMBER() OVER (PARTITION BY permit_si_no ORDER BY issuance_date DESC) = 1
