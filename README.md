# Capstone Project — Level Up: Advanced SQL for Data Engineering

A running project built up module by module across the specialization. Each
module's concept gets applied here as a real piece of the pipeline, instead
of staying a one-off exercise. Targets DuckDB locally — no server/cloud
setup required.

## Current state: raw layer only

Right now this repo has synthetic "messy" source data and light staging
models (typing/trimming only — no dedup, no reconciliation, no history
logic yet). That's intentional: the mess is the point, and future modules
clean it up.

```
Capstone Project/
├── dbt_project.yml / profiles.yml   # DuckDB, local, self-contained
├── seeds/
│   ├── crm_customers.csv            # source A — see "Known issues" below
│   ├── ecommerce_customers.csv      # source B — conflicts with A
│   └── orders.csv                   # fact table, keyed to crm customer_id
├── data/raw_json/*.json             # daily event batches, nested metadata
└── models/staging/
    ├── stg_crm_customers.sql        # trim/cast only, duplicates preserved
    ├── stg_ecommerce_customers.sql  # trim/cast only, not reconciled
    ├── stg_orders.sql               # trim/cast only
    └── stg_customer_events.sql      # flattens JSON via read_json_auto
```

## One-time per terminal session

```bash
cd "Capstone Project"
source .venv/bin/activate
```

```bash
dbt seed --profiles-dir .
dbt run  --profiles-dir .
dbt show --select stg_customer_events --profiles-dir .   # spot-check
```

## Known issues in the raw data (deliberate — this is the point)

**`crm_customers`**
- Same `customer_id` appears twice for ~15% of customers, with a later
  `updated_at` and a changed `region`/`phone` — simulates a source system
  that overwrites in place rather than versioning. Raw material for an
  **SCD2** model.
- Inconsistent name casing, stray whitespace in some emails, some blank
  `region` values, phone numbers in three different formats (or missing).

**`ecommerce_customers`**
- Different identity scheme entirely (`EC-xxxx` strings vs CRM's integer
  `customer_id`) — no shared key, only a fuzzy join on email.
- `full_name` instead of first/last, `country` instead of `region`, email
  casing drift (some `UPPER@EXAMPLE.COM`), and a couple of exact-duplicate
  rows from (simulated) accidental double ingestion.
- ~26 customers overlap with CRM by email; the rest are net-new,
  e-commerce-only customers with no CRM record at all.

Together these two sources are what a **reconciliation-rules** model needs
to resolve into a single customer identity, and the exact-duplicate rows are
a natural fit for a **checksum**-based dedup step.

**`orders`**
- Keyed only to CRM `customer_id`. Deliberately has no `region` column —
  regional analysis requires joining through the (unreconciled) customer
  dimension, which is the point: it forces the reconciliation work to
  matter downstream, not just as an academic exercise.

**`data/raw_json/events_*.json`**
- One file per day, array of event objects with a nested `metadata` object
  (`device`, `ip_country`) — needs flattening, handled in
  `stg_customer_events.sql` via DuckDB's `read_json_auto`.
- A handful of events reference `customer_id` 9991-9993, which don't exist
  in `crm_customers` — orphan records, left unresolved on purpose.

## Roadmap (fill in as each module is covered)

| Module concept | Status | Where it'll land |
|---|---|---|
| Parameterized models (Module 1) | done separately in `Course 1/Module 1/` | — |
| Env/config-driven generation (Module 4) | not started | likely `dbt_project.yml` vars / `target` profiles |
| Checksums (Module 7) | not started | new model, e.g. `models/cleansing/dedup_ecommerce_customers.sql` |
| SCD2 (Module 8) | not started | new model over `stg_crm_customers` |
| Reconciliation rules (Module 10) | not started | new model joining both customer sources |
| Batch JSON transformation (Module 12) | staging done | `stg_customer_events.sql` — later modules may add validation/enrichment |

Update this table as you go — it's the map of what's real vs. still ahead.
