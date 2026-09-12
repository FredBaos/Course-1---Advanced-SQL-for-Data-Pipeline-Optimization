{{ config(enabled=false) }}

/*
  Model: dedup_ecommerce_customers
  Concept: Checksums (Module 7) — TODO, not started

  Disabled via config(enabled=false) above so it doesn't build yet --
  flip that to true (or delete the config line) once it's real.

  BUSINESS CONTEXT
  -----------------
  stg_ecommerce_customers passes the raw ecommerce_customers seed through
  untouched, duplicates included. Per the README "Known issues", a handful
  of rows are exact duplicates from a simulated accidental double
  ingestion (same customer, same everything, inserted twice). This model
  should collapse those down to one row per real customer using a
  checksum/hash of each row's business columns -- there's no clean natural
  key to dedup on instead (see stg_ecommerce_customers).

  TODO (fill in once Module 7 is covered)
  ---------------------------------------------------------
  [ ] Decide which columns make up a row's "identity" for hashing purposes.
  [ ] Compute a checksum/hash column per row (e.g. MD5 of the concatenated,
      normalized column values).
  [ ] Dedup on that checksum -- keep exactly one row per distinct checksum.
  [ ] Confirm the row count drops by exactly the known exact-duplicate
      count (see README "ecommerce_customers" known issues) and nothing
      else gets collapsed that shouldn't be.
  [ ] Point models/marts/dim_customers_reconciled.sql (Module 10) at this
      model instead of stg_ecommerce_customers directly, once it's real.
  [ ] Flip config(enabled=false) above to true.
*/

SELECT * FROM {{ ref('stg_ecommerce_customers') }}
