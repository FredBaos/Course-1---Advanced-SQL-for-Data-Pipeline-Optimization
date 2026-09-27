-- Module 8: dim_crm_customers_scd2 must have exactly one is_current = true
-- row per customer_id. This is a cross-row invariant (not a single-column
-- property), so it's a singular test rather than a generic schema.yml one --
-- dbt fails this test if it returns any rows.

SELECT
    customer_id,
    COUNT(*) FILTER (WHERE is_current) AS n_current
FROM {{ ref('dim_crm_customers_scd2') }}
GROUP BY customer_id
HAVING COUNT(*) FILTER (WHERE is_current) <> 1
