-- Clean and standardize DOB NOW job application filings
-- One row per job filing (job_filing_number)

WITH source AS (
    SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
    SELECT
        -- Keep all other columns as-is (date columns are already TIMESTAMPs)
        * EXCEPT (
            job_filing_number, bin, bbl,
            job_type, filing_status, building_type, initial_cost,
            house_no, street_name, borough, postcode, commmunity_board,
            council_district, census_tract, nta, latitude, longitude,
            zip, city, state, owner_s_business_name,
            existing_dwelling_units, proposed_dwelling_units,
            existing_stories, proposed_no_of_stories,
            existing_height, proposed_height, total_construction_floor_area
        ),

        -- Identifiers
        UPPER(TRIM(job_filing_number)) AS job_filing_number,
        -- Job number without the filing suffix (e.g. "-I1"), for counting projects
        SPLIT(UPPER(TRIM(job_filing_number)), '-')[SAFE_OFFSET(0)] AS job_number,
        -- Null out DOB's borough-level placeholder BINs
        CASE
            WHEN REGEXP_CONTAINS(TRIM(bin), r'^[1-5]000000$') THEN NULL
            ELSE NULLIF(TRIM(bin), '')
        END AS bin,
        NULLIF(TRIM(bbl), '') AS bbl,

        -- Job details
        UPPER(TRIM(job_type)) AS job_type,
        UPPER(TRIM(filing_status)) AS filing_status,
        UPPER(TRIM(building_type)) AS building_type,

        -- Numbers stored as text: strip "$", commas, spaces, then cast
        SAFE_CAST(REGEXP_REPLACE(initial_cost, r'[$,\s]', '') AS NUMERIC) AS initial_cost,
        SAFE_CAST(existing_dwelling_units AS NUMERIC) AS existing_dwelling_units,
        SAFE_CAST(proposed_dwelling_units AS NUMERIC) AS proposed_dwelling_units,
        SAFE_CAST(existing_stories AS NUMERIC) AS existing_stories,
        SAFE_CAST(proposed_no_of_stories AS NUMERIC) AS proposed_stories,
        SAFE_CAST(existing_height AS NUMERIC) AS existing_height,
        SAFE_CAST(proposed_height AS NUMERIC) AS proposed_height,
        SAFE_CAST(REGEXP_REPLACE(total_construction_floor_area, r'[,\s]', '') AS NUMERIC)
            AS total_construction_floor_area,

        -- Location: conformed names/values matching the 311 staging model
        CASE
            WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
            WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
            WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
            WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
            WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
            ELSE 'UNKNOWN or CITYWIDE'
        END AS borough,

        -- Job-site zip (raw `postcode`) becomes the conformed zip
        CASE
            WHEN UPPER(TRIM(postcode)) IN ('N/A', 'NA', '', '00000') THEN NULL
            WHEN REGEXP_CONTAINS(TRIM(postcode), r'^\d{5}(-?\d{4})?$')
                THEN LEFT(TRIM(postcode), 5)
            ELSE NULL
        END AS zip,

        TRIM(house_no) AS house_number,
        -- Collapse runs of spaces (e.g. "WEST   17 STREET")
        REGEXP_REPLACE(UPPER(TRIM(street_name)), r'\s+', ' ') AS street_name,
        TRIM(commmunity_board) AS community_board,
        TRIM(council_district) AS council_district,
        TRIM(census_tract) AS census_tract,
        TRIM(nta) AS nta,
        CAST(latitude AS DECIMAL) AS latitude,
        CAST(longitude AS DECIMAL) AS longitude,

        -- Owner mailing address: renamed so it isn't confused with the job site
        TRIM(zip) AS owner_zip,
        TRIM(city) AS owner_city,
        TRIM(state) AS owner_state,
        TRIM(owner_s_business_name) AS owner_business_name

    FROM source
),

final AS (
    SELECT
        *,
        -- How many raw rows shared this filing number (1 = no duplicate)
        COUNT(*) OVER (PARTITION BY job_filing_number) AS source_row_count,

        -- Metadata
        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM cleaned

    -- Filters
    WHERE borough != 'UNKNOWN or CITYWIDE'
      AND filing_date IS NOT NULL
      AND filing_date >= TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 7 YEAR))

    -- Deduplicate: most recent status update wins; remaining ties broken
    -- deterministically so every dbt run keeps the same row
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY current_status_date DESC,
                 filing_date DESC,
                 approved_date DESC,
                 filing_status,
                 applicant_license
    ) = 1
)

SELECT * FROM final
-- All should be part of this table after running: stg_nyc_dob_job_apps