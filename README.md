# Capstone Project — Course 1 - Advanced SQL for Data Pipeline Optimization

This project has been built as inspiration from the first course of the Coursera "Level Up: Advanced SQL for Data Engineering" certification: "Advanced SQL for Data Pipeline Optimization".

A running project built up module by module across the specialization. Each
module's concept gets applied here as a real piece of the pipeline, instead
of staying a one-off exercise. Targets DuckDB locally — no server/cloud
setup required.

## Current state: raw layer + one parameterized mart

The repo has synthetic "messy" source data, light staging models
(typing/trimming only — no dedup, no reconciliation, no history logic yet),
and one mart model that applies the Module 1 concept (parameterized dbt
pipelines). That's intentional: the mess is the point, and future modules
clean it up.

```
.
├── dbt_project.yml / profiles.yml   # DuckDB, local, self-contained; vars: block for Module 1
├── requirements.txt                 # pinned Python deps (dbt-duckdb)
├── seeds/
│   ├── crm_customers.csv            # source A — see "Known issues" below
│   ├── ecommerce_customers.csv      # source B — conflicts with A
│   └── orders.csv                   # fact table, keyed to crm customer_id
├── data/raw_json/*.json             # daily event batches, nested metadata
└── models/
    ├── staging/
    │   ├── stg_crm_customers.sql        # trim/cast only, duplicates preserved
    │   ├── stg_ecommerce_customers.sql  # trim/cast only, not reconciled
    │   ├── stg_orders.sql               # trim/cast only
    │   └── stg_customer_events.sql      # flattens JSON via read_json_auto
    └── marts/
        └── daily_sales_summary.sql      # Module 1 — parameterized via dbt vars
```

## Setting up the project from scratch

These steps take you from a fresh clone to a working local pipeline. You
only need to do this once per machine (or whenever `.venv` gets wiped).

**Prerequisites:** Python 3.9+ and git.

1. **Get the code.**
   ```bash
   git clone https://github.com/FredBaos/Course-1---Advanced-SQL-for-Data-Pipeline-Optimization.git
   cd "Course-1---Advanced-SQL-for-Data-Pipeline-Optimization"
   ```

2. **Create and activate a virtual environment.**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate          # Windows: .venv\Scripts\activate
   ```

3. **Install dependencies.**
   ```bash
   pip install --upgrade pip
   pip install -r requirements.txt
   ```
   This installs `dbt-duckdb`, which pulls in `dbt-core` and `duckdb` as
   transitive dependencies — no separate database server to install or run.

4. **Verify the dbt profile resolves.**
   ```bash
   dbt debug --profiles-dir .
   ```
   `profiles.yml` lives in the project root (not `~/.dbt/`), so every dbt
   command in this repo needs `--profiles-dir .`. It points at a local
   `dev.duckdb` file that dbt creates on first run — no credentials needed.

5. **Load the seeds and build the models.**
   ```bash
   dbt seed --profiles-dir .
   dbt run  --profiles-dir .
   dbt show --select stg_customer_events --profiles-dir .   # spot-check
   ```

At this point `dev.duckdb` contains the raw seeds plus the staging views
described below. `dev.duckdb`, `.venv/`, `target/`, and `logs/` are all
gitignored — they're regenerated locally and never committed.

## Day-to-day (after initial setup)

Once `.venv` exists, each new terminal session just needs:

```bash
source .venv/bin/activate
dbt run --profiles-dir .
```

## Module 1 — `daily_sales_summary` (parameterized model)

`models/marts/daily_sales_summary.sql` is a daily sales report parameterized
entirely through dbt vars — no hardcoded dates or filters. Defaults live in
the `vars:` block in `dbt_project.yml`; override any of them per run with
`--vars`, no code changes needed:

```bash
# default params (2024-01-13, status=completed, all categories)
dbt run --profiles-dir .

# 3-day window, drill into one category (turns on the high_value_sales column)
dbt run --profiles-dir . --vars '{"analysis_date": "2024-01-13", "date_range_days": 3, "target_category": "Electronics"}'

# different status, same date
dbt run --profiles-dir . --vars '{"order_status": "pending"}'
```

Params: `analysis_date`, `date_range_days`, `order_status`, `target_category`
(`'All'` or one of the five `product_category` values), and
`high_value_threshold`. Full details — including why this uses
`target_category` instead of the course exercise's `target_region` — are in
the docstring at the top of the model file.

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
  matter downstream, not just as an academic exercise. This is also why
  `daily_sales_summary` (Module 1) parameterizes on `product_category`
  rather than region — a real regional join has to wait for reconciliation.

**`data/raw_json/events_*.json`**
- One file per day, array of event objects with a nested `metadata` object
  (`device`, `ip_country`) — needs flattening, handled in
  `stg_customer_events.sql` via DuckDB's `read_json_auto`.
- A handful of events reference `customer_id` 9991-9993, which don't exist
  in `crm_customers` — orphan records, left unresolved on purpose.

## Roadmap (fill in as each module is covered)

| Module concept | Status | Where it'll land |
|---|---|---|
| Parameterized models (Module 1) | done | `models/marts/daily_sales_summary.sql` + `vars:` in `dbt_project.yml` |
| Env/config-driven generation (Module 4) | not started | likely `dbt_project.yml` vars / `target` profiles |
| Checksums (Module 7) | not started | new model, e.g. `models/cleansing/dedup_ecommerce_customers.sql` |
| SCD2 (Module 8) | not started | new model over `stg_crm_customers` |
| Reconciliation rules (Module 10) | not started | new model joining both customer sources |
| Batch JSON transformation (Module 12) | staging done | `stg_customer_events.sql` — later modules may add validation/enrichment |

Update this table as you go — it's the map of what's real vs. still ahead.
