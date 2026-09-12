{{ config(enabled=false) }}

/*
  Model: dim_customers_reconciled
  Concept: Reconciliation rules (Module 10) — TODO, not started

  Disabled via config(enabled=false) above so it doesn't build yet --
  flip that to true (or delete the config line) once it's real.

  BUSINESS CONTEXT
  -----------------
  crm_customers and ecommerce_customers are two identity systems with no
  shared key -- only a fuzzy join on (normalized, lowercased) email. ~26
  ecommerce customers overlap with CRM by email; the rest are net-new,
  ecommerce-only customers with no CRM record. This model should resolve
  both sources into one customer identity per real person, with documented
  precedence rules for conflicting fields.

  TODO (fill in once Module 10 is covered)
  ---------------------------------------------------------
  [ ] Normalize email on both sides (trim, lowercase) as the join key.
  [ ] Decide precedence rules for columns that exist on both sides or
      conflict (e.g. does CRM region win over ecommerce country? whose
      name format becomes canonical -- full_name vs first/last?).
  [ ] Emit one row per resolved customer: CRM-only, ecommerce-only, and
      matched-by-email customers all need to land at the same grain in the
      same table.
  [ ] Decide inputs: raw stg_crm_customers/stg_ecommerce_customers, or
      the Module 7 dedup output (models/cleansing/dedup_ecommerce_customers)
      and Module 8 current-row slice (models/history/dim_crm_customers_scd2)
      once those exist -- probably the latter, so reconciliation runs on
      already-cleaned inputs rather than redoing that work here.
  [ ] This is what finally makes regional analysis on `orders` possible
      (see README "orders" known issues) -- once this model exists,
      revisit daily_sales_summary (Module 1) and consider adding a real
      target_region param back via a join through this table.
  [ ] Flip config(enabled=false) above to true.
*/

SELECT * FROM {{ ref('stg_crm_customers') }}
