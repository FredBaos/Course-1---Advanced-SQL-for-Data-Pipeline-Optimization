{#
  Module 12 material: raw JSON batches under data/raw_json/*.json, one file
  per day, flattened here. A few customer_ids (9991-9993) intentionally
  don't exist in stg_crm_customers -- orphan events from the source system,
  left unresolved for a future model to handle explicitly rather than
  silently dropping them here.

  Path is relative to wherever `dbt` is invoked from -- always run dbt
  commands from this project's root (Capstone Project/).
#}

SELECT
    event_id,
    customer_id,
    event_type,
    CAST(event_ts AS TIMESTAMP)    AS event_ts,
    metadata.device                AS device,
    metadata.ip_country             AS ip_country
FROM read_json_auto('data/raw_json/*.json')
