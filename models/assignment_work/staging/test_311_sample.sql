-- Quick test to verify source connection works
 SELECT
     unique_key,
     created_date,
     complaint_type,
     borough
 FROM {{ source('nyc_homework_raw_data', 'source_nyc_dob_job_apps') }}
 LIMIT 10