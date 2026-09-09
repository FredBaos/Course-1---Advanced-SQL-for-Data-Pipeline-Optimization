{#
  Light typing/trimming only. Deliberately NOT deduplicated: customer_id
  repeats across rows with different updated_at values, simulating change
  history from the source system. That history is raw material for a
  future SCD2 model -- don't collapse it here.
#}

SELECT
    customer_id,
    TRIM(first_name)                AS first_name,
    TRIM(last_name)                 AS last_name,
    LOWER(TRIM(email))              AS email,
    NULLIF(TRIM(phone), '')         AS phone,
    NULLIF(TRIM(region), '')        AS region,
    CAST(signup_date AS DATE)       AS signup_date,
    CAST(updated_at AS DATE)        AS updated_at
FROM {{ ref('crm_customers') }}
