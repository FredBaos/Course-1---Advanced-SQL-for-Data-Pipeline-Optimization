{{ config(enabled=true) }}

/*
  Model: dedup_ecommerce_customers
  Concept: Checksums (Module 7) — done

  BUSINESS CONTEXT
  -----------------
  stg_ecommerce_customers passes the raw ecommerce_customers seed through
  untouched, duplicates included. Per the README "Known issues", a handful
  of rows are exact duplicates from a simulated accidental double
  ingestion (same customer, same everything, inserted twice). There's no
  clean natural key to dedup on -- ecommerce_customer_id is unique per row
  even for the duplicated ones -- so this model hashes each row's business
  columns into a checksum and keeps one row per distinct checksum.

  IDENTITY COLUMNS
  -----------------
  full_name, email, phone, country, created_at -- every business column
  from stg_ecommerce_customers except the surrogate id. Chosen by grouping
  on that set and confirming the only groups with COUNT(*) > 1 were the
  known accidental-duplicate rows (see README "Exploring data locally").

  VERIFIED
  -----------------
  stg_ecommerce_customers: 40 rows -> dedup_ecommerce_customers: 38 rows,
  a drop of 2 matching the known duplicate count, and re-running the
  duplicate-check query against this model's output returns zero groups.
  See README "Testing a model change like this" for the check itself.

  STILL OPEN
  -----------------
  [ ] Add a formal schema.yml `unique` test on row_checksum (currently
      verified manually).
  [ ] Point models/marts/dim_customers_reconciled.sql (Module 10) at this
      model instead of stg_ecommerce_customers directly, once Module 10
      exists.
*/

WITH hashed AS (
    SELECT
        *,
        MD5(
            CONCAT_WS('|',
                full_name,
                email,
                phone,
                country,
                CAST(created_at AS VARCHAR)
            )
        ) AS row_checksum
    FROM {{ ref('stg_ecommerce_customers') }}
)
SELECT * EXCLUDE (row_checksum)
FROM hashed
QUALIFY ROW_NUMBER() OVER (PARTITION BY row_checksum ORDER BY ecommerce_customer_id) = 1

