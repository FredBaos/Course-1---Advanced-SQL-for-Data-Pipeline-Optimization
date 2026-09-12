{#
  Module 12 material: raw JSON batches under data/raw_json/*.json, one file
  per day, flattened here. A few customer_ids (9991-9993) intentionally
  don't exist in stg_crm_customers -- orphan events from the source system,
  left unresolved for a future model to handle explicitly rather than
  silently dropping them here.

  Path is relative to wherever `dbt` is invoked from -- always run dbt
  commands from this project's root.

  TODO (Module 12 continued — batch JSON validation/enrichment): not
  started. This model only flattens; it does nothing with the orphan
  events or with malformed/missing fields. Once Module 12's later material
  is covered:
    [ ] Decide how to surface the 9991-9993 orphans -- a boolean flag
        column here (e.g. is_orphan_customer), or filter them out into a
        separate quarantine model instead of silently including them in
        every downstream join.
    [ ] Validate metadata.device / metadata.ip_country -- what should
        happen on a null or unexpected value? (Currently just passed
        through as-is, nulls included.)
    [ ] Consider whether event_type needs normalizing (casing, a known
        set of allowed values) the way the customer staging models trim
        strings.
#}

SELECT
    event_id,
    customer_id,
    event_type,
    CAST(event_ts AS TIMESTAMP)    AS event_ts,
    metadata.device                AS device,
    metadata.ip_country             AS ip_country
FROM read_json_auto('data/raw_json/*.json')
