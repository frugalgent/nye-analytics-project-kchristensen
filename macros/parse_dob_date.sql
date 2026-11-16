{#
  DOB Permit Issuance stores dates as text in mixed formats
  (mostly MM/DD/YYYY, some YYYY-MM-DD). Try both; return NULL if neither parses.
  LEFT(..., 10) drops any time portion.
#}
{% macro parse_dob_date(col) -%}
    COALESCE(
        SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST({{ col }} AS STRING)), 10)),
        SAFE.PARSE_DATE('%Y-%m-%d', LEFT(TRIM(CAST({{ col }} AS STRING)), 10))
    )
{%- endmacro %}