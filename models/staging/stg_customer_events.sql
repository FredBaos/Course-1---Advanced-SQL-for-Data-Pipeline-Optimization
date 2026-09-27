{{ config(enabled=true) }}

/*
  Model: stg_customer_events
  Concept: Batch JSON transformation, validation & enrichment (Module 12) — done

  Raw JSON batches under data/raw_json/ (one *.json file per day),
  flattened here. A few customer_ids (9991-9993) intentionally don't exist
  in stg_crm_customers -- orphan events from the source system.

  Path is relative to wherever `dbt` is invoked from -- always run dbt
  commands from this project's root.

  VALIDATION / ENRICHMENT
  -----------------
  event_type and device are each a closed, known set (5 and 3 values
  respectively) -- normalized to lowercase/trimmed, with anything outside
  the known set falling back to 'unknown' as a defensive guard against
  future bad data. ip_country has no fixed enum (any country name is
  valid), so it's only null/blank-guarded, not validated against a list.
  is_orphan_customer flags the 9991-9993 rows via a NOT EXISTS check
  against stg_crm_customers, surfaced as a column rather than a separate
  quarantine model -- orphans are a known, small, intentional feature of
  this data, not noise to hide from downstream joins.

  VERIFIED
  -----------------
  55 rows total, 7 flagged is_orphan_customer (9991 x2, 9992 x2, 9993 x3,
  matching the known orphan set), zero rows with device/event_type/
  ip_country = 'unknown' -- the current data is actually clean on all
  three fields, so the 'unknown' fallback is guarding against data that
  doesn't exist yet, not fixing anything broken today.
*/

SELECT
    e.event_id,
    e.customer_id,
    CASE
        WHEN LOWER(TRIM(e.event_type)) IN ('page_view', 'login', 'logout', 'add_to_cart', 'checkout_start')
        THEN LOWER(TRIM(e.event_type))
        ELSE 'unknown'
    END AS event_type,
    CAST(e.event_ts AS TIMESTAMP)    AS event_ts,
    CASE
        WHEN LOWER(TRIM(e.metadata.device)) IN ('desktop', 'mobile', 'tablet')
        THEN LOWER(TRIM(e.metadata.device))
        ELSE 'unknown'
    END AS device,
    COALESCE(NULLIF(TRIM(e.metadata.ip_country), ''), 'unknown') AS ip_country,
    NOT EXISTS (
        SELECT 1 FROM {{ ref('stg_crm_customers') }} c
        WHERE c.customer_id = e.customer_id
    ) AS is_orphan_customer
FROM read_json_auto('data/raw_json/*.json') AS e

