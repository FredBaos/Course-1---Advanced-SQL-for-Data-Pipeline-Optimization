{#
  Light typing/trimming only. Deliberately NOT reconciled against
  stg_crm_customers here: different id scheme (EC-xxxx vs integer),
  combined full_name vs first/last, country vs region, and email casing
  drift are all left in place for a future reconciliation-rules model.
#}

SELECT
    ecommerce_customer_id,
    TRIM(full_name)                    AS full_name,
    LOWER(TRIM(email_address))         AS email,
    NULLIF(TRIM(phone_number), '')     AS phone,
    TRIM(country)                      AS country,
    CAST(created_at AS DATE)           AS created_at
FROM {{ ref('ecommerce_customers') }}
