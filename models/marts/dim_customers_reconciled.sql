{{ config(enabled=true) }}

/*
  Model: dim_customers_reconciled
  Concept: Reconciliation rules (Module 10) — done

  BUSINESS CONTEXT
  -----------------
  crm_customers and ecommerce_customers are two identity systems with no
  shared key -- only a fuzzy join on (normalized, lowercased) email. 26
  ecommerce customers overlap with CRM by email; the rest are net-new,
  ecommerce-only customers with no CRM record. This model resolves both
  sources into one customer identity per real person, with precedence
  rules for conflicting fields.

  INPUTS
  -----------------
  Reads from Module 7's dedup output (dedup_ecommerce_customers) and
  Module 8's current-row SCD2 slice (dim_crm_customers_scd2 WHERE
  is_current) rather than the raw staging models -- both staging models
  already normalize email (trim, lowercase), so the join key needed no
  extra work here.

  JOIN
  -----------------
  FULL OUTER JOIN on email, keeping all three groups at one grain: matched
  (26), CRM-only (19), ecommerce-only (12) = 57 total rows.

  PRECEDENCE RULES
  -----------------
  CRM wins when both sources have the customer (older, more authoritative
  system of record); ecommerce fields fill in only where there's no
  matching CRM record. name: CRM first_name+last_name, else ecommerce
  full_name. phone: CRM phone, else ecommerce phone. region/country are
  different taxonomies, not just formatting drift -- kept as separate raw
  columns for transparency, plus a merged resolved_region that
  daily_sales_summary.sql (Module 1) now joins through via its
  target_region param.

  NAME CASING
  -----------------
  CRM has ALL-CAPS rows for a subset of customers (e.g. "PRIYA IVANOV",
  "NOAH KIM") even after staging's TRIM-only pass. Precedence alone doesn't
  fix this -- it just picks the right source, casing and all -- so the
  final name is normalized to title case: lowercase everything, then
  uppercase the first letter of each space-separated word. No DuckDB
  initcap() in this version, so this is hand-rolled via
  string_split/list_transform/array_to_string. Confirmed no
  hyphenated/apostrophe names exist in either source (a plain space-split
  title-case would mishandle e.g. "smith-jones" -> "Smith-jones"), so this
  approach is safe for this dataset as-is; revisit if that assumption ever
  changes.

  VERIFIED
  -----------------
  57 rows, zero duplicate emails, 26/19/12 group split matches expected,
  zero rows with name IS NULL. Customer 1033 (different phone on each
  side) resolves to the CRM phone. Customer 1045 (CRM casing issue,
  "PRIYA IVANOV") now resolves to "Priya Ivanov".

  Downstream: daily_sales_summary.sql (Module 1) reads resolved_region via
  its target_region param -- done, see README Module 1 section.
*/

WITH crm_current AS (
    SELECT *
    FROM {{ ref('dim_crm_customers_scd2') }}
    WHERE is_current
),
ec AS (
    SELECT * FROM {{ ref('dedup_ecommerce_customers') }}
),

resolved AS (
    SELECT
        crm_current.customer_id,
        ec.ecommerce_customer_id,
        COALESCE(crm_current.email, ec.email) AS email,

        -- Precedence: CRM wins when both sources have the customer (older,
        -- more authoritative system of record); ecommerce fields fill in only
        -- for customers with no matching CRM record at all.
        COALESCE(
            TRIM(crm_current.first_name || ' ' || crm_current.last_name),
            ec.full_name
        ) AS name,
        COALESCE(crm_current.phone, ec.phone) AS phone,

        -- region (CRM) and country (ecommerce) are different taxonomies, not
        -- just formatting drift -- kept raw for transparency, plus a merged
        -- best-effort label for the future target_region join (Module 1 TODO).
        crm_current.region,
        ec.country,
        COALESCE(crm_current.region, ec.country) AS resolved_region
    FROM crm_current
    FULL OUTER JOIN ec
        ON ec.email = crm_current.email
)

SELECT
    customer_id,
    ecommerce_customer_id,
    email,
    -- Title-case the resolved name so CRM's ALL-CAPS rows don't leak
    -- through untouched (see NAME CASING above).
    array_to_string(
        list_transform(
            string_split(LOWER(name), ' '),
            part -> upper(substr(part, 1, 1)) || substr(part, 2)
        ),
        ' '
    ) AS name,
    phone,
    region,
    country,
    resolved_region
FROM resolved
