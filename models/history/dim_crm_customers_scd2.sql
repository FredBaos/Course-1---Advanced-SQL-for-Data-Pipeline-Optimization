{{ config(enabled=true) }}

/*
  Model: dim_crm_customers_scd2
  Concept: SCD Type 2 (Module 8) — done

  BUSINESS CONTEXT
  -----------------
  ~15% of crm_customers customer_id values appear twice, with a later
  updated_at and a changed region/phone (see README "Known issues") --
  simulating a source system that overwrites in place instead of
  versioning. This model turns that overwrite-in-place pattern into a
  proper SCD2 dimension: one row per (customer_id, version), with
  valid_from/valid_to bounds and a current-row flag, so downstream models
  can ask "what did we believe about this customer on date X" instead of
  only ever seeing the latest overwrite.

  APPROACH
  -----------------
  Hand-rolled window functions over stg_crm_customers, not a dbt snapshot --
  both versions of a changed customer already sit as two static rows in the
  one seed load, which is a shape dbt snapshot (built for detecting changes
  across successive dbt runs) doesn't reconstruct.
  version_number: ROW_NUMBER() PARTITION BY customer_id ORDER BY updated_at.
  valid_from: this row's own updated_at. valid_to: LEAD(updated_at) over the
  same window -- NULL when there's no next version. is_current: valid_to
  IS NULL, kept as an explicit column.

  VERIFIED
  -----------------
  51 rows in stg_crm_customers -> 51 rows out (SCD2 annotates history, it
  doesn't drop or add rows), 45 distinct customer_id, exactly 45
  is_current = true rows (one per customer), no row with valid_from >
  valid_to. See README "Testing this one" (Module 8 section) for the checks.

  TESTING
  -----------------
  "Exactly one is_current row per customer_id" is a cross-row invariant,
  not a single-column property, so it's a singular test rather than a
  schema.yml generic one -- see
  tests/assert_one_current_row_per_crm_customer.sql.

  Point models/marts/dim_customers_reconciled.sql (Module 10) at this
  model's current-row slice instead of stg_crm_customers directly -- done,
  see README Module 10.
*/

SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at) AS version_number,
    updated_at AS valid_from,
    LEAD(updated_at) OVER (PARTITION BY customer_id ORDER BY updated_at) AS valid_to,
    valid_to IS NULL AS is_current
FROM {{ ref('stg_crm_customers') }}
