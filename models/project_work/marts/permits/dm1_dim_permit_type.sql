-- DM1_DimPermitType (permits mart only)
-- Grain: one row per distinct job_type / work_type / permit_type / filing_status / permit_status.
-- Low-cardinality attributes pulled out of the fact so the fact stays narrow.

WITH stg_permits AS (
    SELECT * FROM {{ ref('stg_dob_permits') }}
),

distinct_permit_types AS (
    SELECT DISTINCT
        job_type,
        work_type,
        permit_type,
        filing_status,
        permit_status
    FROM stg_permits
)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'job_type', 'work_type', 'permit_type', 'filing_status', 'permit_status'
    ]) }} AS permit_type_key,
    job_type,
    work_type,
    permit_type,
    filing_status,
    permit_status
FROM distinct_permit_types
