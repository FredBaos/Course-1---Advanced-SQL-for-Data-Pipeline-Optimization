{{ config(enabled=false) }}

/*
  Model: dim_crm_customers_scd2
  Concept: SCD Type 2 (Module 8) — TODO, not started

  Disabled via config(enabled=false) above so it doesn't build yet --
  flip that to true (or delete the config line) once it's real.

  BUSINESS CONTEXT
  -----------------
  ~15% of crm_customers customer_id values appear twice, with a later
  updated_at and a changed region/phone (see README "Known issues") --
  simulating a source system that overwrites in place instead of
  versioning. This model should turn that overwrite-in-place pattern into
  a proper SCD2 dimension: one row per (customer_id, version), with
  valid_from/valid_to bounds and a current-row flag, so downstream models
  can ask "what did we believe about this customer on date X" instead of
  only ever seeing the latest overwrite.

  TODO (fill in once Module 8 is covered)
  ---------------------------------------------------------
  [ ] Order each customer_id's rows by updated_at to establish version
      sequence.
  [ ] Derive valid_from (this version's updated_at) and valid_to (the next
      version's updated_at, or NULL/far-future for the current version).
  [ ] Add an is_current boolean (or a dbt_valid_to IS NULL convention).
  [ ] Decide: hand-rolled SQL (window functions over stg_crm_customers) or
      dbt's built-in snapshot feature (a snapshots/ definition + `dbt
      snapshot`) -- the snapshot approach tracks changes run-over-run
      rather than reconstructing history from the two static versions
      already sitting in the seed, so pick based on what Module 8 actually
      teaches.
  [ ] Point models/marts/dim_customers_reconciled.sql (Module 10) at this
      model's current-row slice instead of stg_crm_customers directly,
      once it's real.
  [ ] Flip config(enabled=false) above to true.
*/

SELECT * FROM {{ ref('stg_crm_customers') }}
