# dbt Messy Data Lab

A hands-on dbt + DuckDB project for working through real data-pipeline
problems — deduplication, slowly changing dimensions, identity
reconciliation, batch JSON validation — on deliberately messy synthetic
data, rather than as isolated one-off exercises. Targets DuckDB locally —
no server/cloud setup required.

Originally started as inspiration from the first course of the Coursera
"Level Up: Advanced SQL for Data Engineering" certification: "Advanced SQL
for Data Pipeline Optimization" — the module numbering below (1, 4, 7, 8,
10, 12) still reflects that course's structure, though this repo has since
grown into its own standalone project.

## Current state: every planned module is implemented

The repo has synthetic "messy" source data, light staging models
(typing/trimming only, plus Module 12's JSON validation/enrichment on the
events staging model — reconciliation/history logic itself still lives
downstream, not at the staging layer), a mart model that applies the
Module 1 (parameterized pipelines) and Module 4 (env/config-driven
generation) concepts together, a cleansing model that applies Module 7
(checksums) to collapse `ecommerce_customers`' exact-duplicate rows, a
history model that applies Module 8 (SCD2) to turn `crm_customers`'
overwrite-in-place changes into a proper versioned dimension, and a
reconciliation mart that applies Module 10 to resolve both customer
sources into one identity per real person. That's intentional: the mess
was the point, and each module cleaned up (or enriched) one more piece
of it.

```
.
├── dbt_project.yml / profiles.yml   # DuckDB, local, self-contained; vars: (Module 1, incl. target_region) + dev/prod targets (Module 4)
├── requirements.txt                 # pinned Python deps (dbt-duckdb)
├── seeds/
│   ├── crm_customers.csv            # source A — see "Known issues" below
│   ├── ecommerce_customers.csv      # source B — conflicts with A
│   └── orders.csv                   # fact table, keyed to crm customer_id
├── data/raw_json/*.json             # daily event batches, nested metadata
├── tests/
│   └── assert_one_current_row_per_crm_customer.sql # Module 8 invariant test
└── models/
    ├── staging/
    │   ├── stg_crm_customers.sql        # trim/cast only, duplicates preserved
    │   ├── stg_ecommerce_customers.sql  # trim/cast only, not reconciled
    │   ├── stg_orders.sql               # trim/cast only
    │   └── stg_customer_events.sql      # Module 12 — JSON validation/enrichment, done
    ├── marts/
    │   ├── daily_sales_summary.sql      # Module 1 — parameterized via dbt vars, done (incl. target_region via Module 10)
    │   └── dim_customers_reconciled.sql # Module 10 — reconciliation rules, done
    ├── cleansing/
    │   ├── dedup_ecommerce_customers.sql # Module 7 — checksum-based dedup, done
    │   └── schema.yml                    # unique/not_null test on row_checksum
    └── history/
        └── dim_crm_customers_scd2.sql   # Module 8 — SCD2 history, done
```

All four planned modules (7, 8, 10, 12) are now implemented, enabled, and
verified. See Module 7, 8, 10, or 12 below for the skeleton → real-logic
pattern each one followed.

## Setting up the project from scratch

These steps take you from a fresh clone to a working local pipeline. You
only need to do this once per machine (or whenever `.venv` gets wiped).

**Prerequisites:** Python 3.9+ and git.

1. **Get the code.**
   ```bash
   git clone https://github.com/FredBaos/dbt-messy-data-lab.git
   cd dbt-messy-data-lab
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
described below. `*.duckdb` (both `dev.duckdb` and `prod.duckdb` — see
Module 4 below), `.venv/`, `target/`, and `logs/` are all gitignored —
they're regenerated locally and never committed.

## Day-to-day (after initial setup)

Once `.venv` exists, each new terminal session just needs:

```bash
source .venv/bin/activate
dbt run --profiles-dir .
```

## Exploring data locally (before writing a model)

For quick, throwaway exploration -- e.g. deciding which columns define a
row's identity before writing a checksum, or eyeballing a staging model --
drop into a Python shell against `dev.duckdb` directly instead of writing a
one-off `.sql` file:

```bash
source .venv/bin/activate
python3
```
```python
import duckdb
con = duckdb.connect("dev.duckdb")

con.sql("SELECT * FROM ecommerce_customers").show()

# find rows that repeat on a candidate set of identity columns
con.sql("""
    SELECT full_name, email_address, phone_number, country, created_at, COUNT(*) AS n
    FROM ecommerce_customers
    GROUP BY ALL
    HAVING COUNT(*) > 1
""").show()
```

This talks to the same `dev.duckdb` file `dbt run`/`dbt seed` build into, so
it sees seeds and any already-built staging models immediately. No dbt
compile step, no throwaway model file to remember to delete.

## Module 1 — `daily_sales_summary` (parameterized model)

`models/marts/daily_sales_summary.sql` is a daily sales report parameterized
entirely through dbt vars — no hardcoded dates or filters. Defaults live in
the `vars:` block in `dbt_project.yml`; override any of them per run with
`--vars`, no code changes needed:

```bash
# default params (2024-01-13, status=completed, all categories, all regions)
dbt run --profiles-dir .

# 3-day window, drill into one category (turns on the high_value_sales column)
dbt run --profiles-dir . --vars '{"analysis_date": "2024-01-13", "date_range_days": 3, "target_category": "Electronics"}'

# different status, same date
dbt run --profiles-dir . --vars '{"order_status": "pending"}'

# drill into one region (turns on the resolved_region column) -- joins
# through Module 10's dim_customers_reconciled
dbt run --profiles-dir . --vars '{"analysis_date": "2024-01-13", "date_range_days": 3, "target_region": "West"}'
```

Params: `analysis_date`, `date_range_days`, `order_status`, `target_category`
(`'All'` or one of the five `product_category` values), `target_region`
(`'All'` or one of `dim_customers_reconciled.resolved_region`'s values —
see Module 10), and `high_value_threshold`. Full details — including the
history of why this originally used `target_category` instead of the
course exercise's `target_region`, and how `target_region` got added once
Module 10 made a real regional join possible — are in the docstring at the
top of the model file.

## Module 4 — env/config-driven generation (dev vs. prod targets)

`profiles.yml` now defines two targets under the `dbt_messy_data_lab`
profile: `dev` (default, `dev.duckdb`, 4 threads) and `prod` (`prod.duckdb`,
16 threads). Pick one with `--target`:

```bash
dbt run --profiles-dir .                  # dev (default) -- dev.duckdb
dbt run --profiles-dir . --target prod    # prod -- prod.duckdb
```

Two things in this pipeline now branch on which target is active,
via the `target.name` Jinja variable:

- **`dbt_project.yml` vars** — `date_range_days` and `order_status` are set
  per-target instead of one fixed default: `date_range_days` is 1 in dev /
  7 in prod, `order_status` is `pending` in dev / `completed` in prod.
  `--vars` on the CLI still overrides either of these for a single run,
  same as Module 1.
- **`daily_sales_summary.sql`** adds a dev-only `LIMIT 100` at the bottom
  (`{% if target.name == 'dev' %} LIMIT 100 {% endif %}`), so local runs
  against a wide date range stay cheap; `prod` runs are unbounded.

**Gotcha worth knowing:** a target-conditioned var has to be written as a
*quoted* Jinja string, e.g. `date_range_days: "{{ 7 if target.name ==
'prod' else 1 }}"` — unquoted, `{{ }}` collides with YAML's own
flow-mapping syntax and fails to parse. But quoting also means the
rendered value comes back as the **string** `"7"`, not the int `7` (dbt
does not auto-convert it back). Since `daily_sales_summary.sql` does
arithmetic on `date_range_days` (`var('date_range_days', 1) - 1`), it
coerces with the Jinja `| int` filter: `(var('date_range_days', 1) | int)
- 1`. Apply the same `| int` (or `| string`, `| bool`, etc.) to any var you
make target-conditioned and then use in non-string Jinja logic.

## Module 7 — checksums (`dedup_ecommerce_customers`)

`ecommerce_customers` has a couple of exact-duplicate rows from a simulated
accidental double ingestion (see "Known issues" below). There's no clean
natural key to dedup on — `ecommerce_customer_id` is unique per *row*, even
for the duplicated ones — so `models/cleansing/dedup_ecommerce_customers.sql`
hashes each row's business columns into a checksum and keeps one row per
distinct checksum:

```sql
WITH hashed AS (
    SELECT
        *,
        MD5(
            CONCAT_WS('|', full_name, email, phone, country, CAST(created_at AS VARCHAR))
        ) AS row_checksum
    FROM {{ ref('stg_ecommerce_customers') }}
)
SELECT *
FROM hashed
QUALIFY ROW_NUMBER() OVER (PARTITION BY row_checksum ORDER BY ecommerce_customer_id) = 1
```

- **Identity columns**: every business column from `stg_ecommerce_customers`
  except the surrogate id — `full_name`, `email`, `phone`, `country`,
  `created_at`. Chosen by grouping on that set and confirming the only
  groups with `COUNT(*) > 1` were the known accidental-duplicate rows (see
  "Exploring data locally" above for the query used to check this) — too few
  columns would falsely merge distinct customers, including the id would
  never catch a duplicate at all.
- **Checksum**: `MD5(CONCAT_WS('|', ...))` over those columns. Kept in the
  output (not excluded) specifically so it can be tested — see "Testing a
  model change like this" below.
- **Dedup**: `QUALIFY ROW_NUMBER() OVER (PARTITION BY row_checksum ...) = 1`
  keeps exactly one row per checksum.
- **Verified**: `stg_ecommerce_customers` has 40 rows, `dedup_ecommerce_customers`
  has 38 — a drop of 2, matching the known duplicate count — and re-running
  the duplicate-check query against the deduped output returns zero groups.

Model is enabled (`dbt run` builds it), and `dim_customers_reconciled.sql`
(Module 10) reads from this model rather than `stg_ecommerce_customers`
directly.

### Testing a model change like this

The general recipe, used here and worth repeating for any model edit in
this repo:

```bash
source .venv/bin/activate

# 1. compile first -- catches Jinja/SQL syntax errors without materializing
dbt compile --profiles-dir . --select dedup_ecommerce_customers

# 2. build just this model
dbt run --profiles-dir . --select dedup_ecommerce_customers

# 3. eyeball the output
dbt show --profiles-dir . --select dedup_ecommerce_customers --limit 50
```

Then verify row counts and check for leftover duplicates -- via `dbt show
--inline` or the python3/duckdb shell from "Exploring data locally" above:

```python
import duckdb
con = duckdb.connect("dev.duckdb")

before = con.sql("SELECT COUNT(*) FROM stg_ecommerce_customers").fetchone()[0]
after = con.sql("SELECT COUNT(*) FROM dedup_ecommerce_customers").fetchone()[0]
print("dropped:", before - after)   # should equal the known duplicate count

con.sql("""
    SELECT full_name, email, phone, country, created_at, COUNT(*) AS n
    FROM dedup_ecommerce_customers
    GROUP BY ALL
    HAVING COUNT(*) > 1
""").show()   # should return zero rows
```

Two checks, not one: the row-count drop catches *under*-deduping (checksum
missed a real duplicate), the leftover-duplicate-groups check catches
*over*-deduping (checksum too broad, merged distinct customers). A single
before/after count alone can't tell those apart.

`dbt test --profiles-dir . --select dedup_ecommerce_customers` now runs a
real test: `models/cleansing/schema.yml` declares `unique` and `not_null`
on `row_checksum` — a duplicate checksum surviving this model would mean
the dedup itself is broken. That's why `row_checksum` is kept in the output
above rather than excluded.

## Module 8 — SCD2 (`dim_crm_customers_scd2`)

~15% of `crm_customers` `customer_id` values appear twice, with a later
`updated_at` and a changed `region`/`phone` — simulating a source system
that overwrites in place instead of versioning (see "Known issues" below).
`models/history/dim_crm_customers_scd2.sql` turns that overwrite-in-place
pattern into a proper SCD2 dimension: one row per `(customer_id, version)`,
with `valid_from`/`valid_to` bounds and an `is_current` flag, so downstream
models can ask "what did we believe about this customer on date X" instead
of only ever seeing the latest overwrite.

```sql
SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at) AS version_number,
    updated_at AS valid_from,
    LEAD(updated_at) OVER (PARTITION BY customer_id ORDER BY updated_at) AS valid_to,
    valid_to IS NULL AS is_current
FROM {{ ref('stg_crm_customers') }}
```

- **Version sequence**: `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY
  updated_at)` — each customer's rows numbered oldest to newest.
- **`valid_from` / `valid_to`**: `valid_from` is the row's own `updated_at`;
  `valid_to` is the *next* version's `updated_at` via `LEAD(...)` — `NULL`
  when there is no next version (i.e. this is the current row).
- **`is_current`**: falls out of `valid_to IS NULL`. Kept as an explicit
  boolean column (rather than relying on callers to remember the NULL
  convention) for self-documenting downstream joins.
- **Hand-rolled SQL, not a dbt snapshot**: dbt snapshots detect changes
  *across successive dbt runs* of a source that mutates over time. That's
  not this data — both versions of e.g. customer 1007 already sit as two
  static rows in the one seed file, in a single load. Window functions over
  `stg_crm_customers` directly match how this history already exists in the
  seed, rather than trying to make snapshots rediscover it run-over-run.
- **Verified**: 51 rows in `stg_crm_customers` → 51 rows out (SCD2 annotates
  history, it doesn't drop or add rows), 45 distinct `customer_id` values,
  exactly 45 `is_current = true` rows (one per customer, no more, no less),
  no row where `valid_from > valid_to`. Spot-checked customer 1007:
  `region` goes West (`valid_from 2023-12-12, valid_to 2024-04-13,
  is_current false`) → East (`valid_from 2024-04-13, valid_to NULL,
  is_current true`).

Model is enabled (`dbt run` builds it), and `dim_customers_reconciled.sql`
(Module 10) reads from this model's current-row (`is_current`) slice rather
than `stg_crm_customers` directly.

### Testing this one

Same recipe as Module 7 (compile → run → check invariants), but the
invariants for an SCD2 model are different from a dedup model — row count
should stay the *same*, and the thing to actually verify is version
integrity:

```python
import duckdb
con = duckdb.connect("dev.duckdb")

print(con.sql("SELECT COUNT(*) FROM dim_crm_customers_scd2").fetchone()[0])   # 51, same as stg_crm_customers
print(con.sql("SELECT COUNT(DISTINCT customer_id) FROM dim_crm_customers_scd2").fetchone()[0])  # 45

# exactly one is_current = true per customer_id -- breaks every downstream
# join to this model's "current" slice if violated
con.sql("""
    SELECT customer_id, COUNT(*) FILTER (WHERE is_current) AS n_current
    FROM dim_crm_customers_scd2
    GROUP BY customer_id
    HAVING COUNT(*) FILTER (WHERE is_current) <> 1
""").show()   # should return zero rows

# valid_from should never be after valid_to
con.sql("""
    SELECT * FROM dim_crm_customers_scd2
    WHERE valid_to IS NOT NULL AND valid_from > valid_to
""").show()   # should return zero rows
```

The "exactly one current row per customer" check above is now a real test:
`tests/assert_one_current_row_per_crm_customer.sql`. It's a *singular*
test rather than a `schema.yml` generic one, because the invariant spans
multiple rows (a `GROUP BY customer_id HAVING ...`) rather than being a
property of one column — dbt's built-in generic tests
(`unique`/`not_null`/etc.) only check single columns, so a cross-row rule
like this is written as a plain `.sql` file under `tests/` that dbt fails
if it returns any rows.

## Module 10 — reconciliation rules (`dim_customers_reconciled`)

`crm_customers` and `ecommerce_customers` are two identity systems with no
shared key — only a fuzzy join on (already-normalized) email. 26 ecommerce
customers overlap with CRM by email; the rest are net-new, ecommerce-only
customers with no CRM record. `models/marts/dim_customers_reconciled.sql`
resolves both sources into one customer identity per real person.

```sql
WITH crm_current AS (
    SELECT * FROM {{ ref('dim_crm_customers_scd2') }} WHERE is_current
),
ec AS (
    SELECT * FROM {{ ref('dedup_ecommerce_customers') }}
),
resolved AS (
    SELECT
        crm_current.customer_id,
        ec.ecommerce_customer_id,
        COALESCE(crm_current.email, ec.email) AS email,
        COALESCE(
            TRIM(crm_current.first_name || ' ' || crm_current.last_name),
            ec.full_name
        ) AS name,
        COALESCE(crm_current.phone, ec.phone) AS phone,
        crm_current.region,
        ec.country,
        COALESCE(crm_current.region, ec.country) AS resolved_region
    FROM crm_current
    FULL OUTER JOIN ec ON ec.email = crm_current.email
)

SELECT
    customer_id,
    ecommerce_customer_id,
    email,
    array_to_string(
        list_transform(
            string_split(LOWER(name), ' '),
            part -> upper(substr(part, 1, 1)) || substr(part, 2)
        ),
        ' '
    ) AS name,
    phone,
    region,
    country,
    resolved_region
FROM resolved
```

- **Inputs**: Module 7's dedup output and Module 8's current-row SCD2
  slice — not the raw staging models — so reconciliation runs on
  already-cleaned inputs rather than redoing that work. This is exactly why
  Module 8 needed to land before this one: joining raw `stg_crm_customers`
  would have produced duplicate matches for the 6 customers with two
  versions.
- **Join**: `FULL OUTER JOIN` on email keeps all three groups at one
  grain — matched (26), CRM-only (19), ecommerce-only (12) = 57 rows total.
  An `INNER`/`LEFT JOIN` would have silently dropped one or two of those
  groups.
- **Precedence rules**: CRM wins when both sources have the customer
  (older, more authoritative system of record); ecommerce fields fill in
  only where there's no matching CRM record.
  - `name`: CRM `first_name`+`last_name`, else ecommerce `full_name`.
  - `phone`: CRM phone, else ecommerce phone.
  - `region`/`country` are different taxonomies (West/East/South vs.
    USA/Canada), not just formatting drift — kept as separate raw columns
    for transparency, plus a merged `resolved_region` for the future
    `target_region` join.
- **Name casing normalization**: CRM has ALL-CAPS rows for a subset of
  customers (e.g. `PRIYA IVANOV`, `NOAH KIM`) even after staging's TRIM-only
  pass — precedence alone just picks the right source, casing and all, so
  the resolved `name` gets title-cased in a final pass: lowercase, then
  uppercase each space-separated word's first letter. No `initcap()` in
  this DuckDB version, so it's hand-rolled via
  `string_split`/`list_transform`/`array_to_string`. Confirmed neither
  source has hyphenated or apostrophe names (a plain space-split
  title-case would mangle e.g. `smith-jones` → `Smith-jones`), so this is
  safe for this dataset as it stands.
- **Verified**: 57 rows, zero duplicate emails, 26/19/12 group split
  matches expected, zero rows with `name IS NULL`, zero rows where `name`
  is still all-uppercase. Customer 1033 (genuinely different phone numbers
  on each side, not just formatting) resolves to the CRM phone
  `(939) 605-8588`. Customer 1045 (CRM casing issue) now resolves to
  `Priya Ivanov`; already-proper-case ecommerce-only names pass through
  unaffected (title-casing an already-correct name is a no-op).

Model is enabled, and `daily_sales_summary` (Module 1) now has a real
`target_region` param that joins through `resolved_region` — see the
updated Module 1 section above.

### Testing this one

```bash
dbt compile --profiles-dir . --select dim_customers_reconciled
dbt run --profiles-dir . --select dim_customers_reconciled
```

```python
import duckdb
con = duckdb.connect("dev.duckdb")

print(con.sql("SELECT COUNT(*) FROM dim_customers_reconciled").fetchone()[0])   # 57

con.sql("""
    SELECT email, COUNT(*) FROM dim_customers_reconciled
    GROUP BY email HAVING COUNT(*) > 1
""").show()   # should return zero rows -- email was the join key

con.sql("""
    SELECT
        COUNT(*) FILTER (WHERE customer_id IS NOT NULL AND ecommerce_customer_id IS NOT NULL) AS matched,
        COUNT(*) FILTER (WHERE customer_id IS NOT NULL AND ecommerce_customer_id IS NULL) AS crm_only,
        COUNT(*) FILTER (WHERE customer_id IS NULL AND ecommerce_customer_id IS NOT NULL) AS ec_only
    FROM dim_customers_reconciled
""").show()   # should be 26 / 19 / 12

# spot-check a customer with a genuine conflict (not just missing data) to
# confirm precedence actually resolved rather than accidentally picking
# whichever side happened to be non-null
con.sql("SELECT * FROM dim_customers_reconciled WHERE customer_id = 1033").show()

# no name should still be all-uppercase after the title-case pass
con.sql("""
    SELECT customer_id, ecommerce_customer_id, name FROM dim_customers_reconciled
    WHERE name = UPPER(name) AND LENGTH(name) > 1
""").show()   # should return zero rows
```

The join/grain checks (row count, no duplicate emails, group split) verify
the `FULL OUTER JOIN` is correct. The spot-check on a customer with
genuinely conflicting values on both sides is what verifies the precedence
*rule* was actually applied, rather than just confirming the join ran. The
all-uppercase check verifies the title-case normalization actually caught
every affected row, not just the one spot-checked.

## Module 12 — batch JSON validation & enrichment (`stg_customer_events`)

`data/raw_json/*.json` is one file per day, event objects with a nested
`metadata` struct. `stg_customer_events.sql` flattens it and adds three
things: a normalized `event_type`, a normalized `device`, and an
`is_orphan_customer` flag for the handful of events whose `customer_id`
(9991-9993) doesn't exist in `crm_customers` at all.

```sql
SELECT
    e.event_id,
    e.customer_id,
    CASE
        WHEN LOWER(TRIM(e.event_type)) IN ('page_view', 'login', 'logout', 'add_to_cart', 'checkout_start')
        THEN LOWER(TRIM(e.event_type))
        ELSE 'unknown'
    END AS event_type,
    CAST(e.event_ts AS TIMESTAMP) AS event_ts,
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
```

- **`event_type` / `device`**: each a closed, known set (5 and 3 values
  respectively) — normalized to lowercase/trimmed, with anything outside
  the known set falling back to `'unknown'` as a defensive guard against
  *future* bad data. Checked all three raw JSON files directly: every row
  already matches the known set exactly, so this isn't fixing anything
  broken today, it's guarding against data that doesn't exist yet.
- **`ip_country`**: no fixed enum here (any country name is valid, unlike
  `device`), so it's only null/blank-guarded via `COALESCE(NULLIF(...))`,
  not validated against a list.
- **`is_orphan_customer`**: a flag column, not a separate quarantine
  model — the 9991-9993 orphans are a known, small, intentional feature of
  this data (not noise to silently drop), so keeping them in the same
  table with a flag lets downstream models decide whether to include or
  exclude them, rather than making that decision here.
- **Verified**: 55 rows total, 7 flagged `is_orphan_customer` (9991 ×2,
  9992 ×2, 9993 ×3 — matching the known orphan set exactly), zero rows
  with `device`/`event_type`/`ip_country` = `'unknown'`.

**Gotcha worth knowing**: DuckDB supports *nested* block comments, so a
literal `/*` appearing anywhere inside this model's `/* ... */` docstring
— even inside plain prose, e.g. writing out the path
`data/raw_json/*.json` — opens a second nested comment level that the
docstring's single closing `*/` doesn't close, silently commenting out the
entire `SELECT` below it and failing with "unterminated comment." Avoid
writing a literal `/*` sequence inside any `/* */` docstring in this repo
(here, that meant rewording the path reference to
`data/raw_json/ (*.json files)` instead).

Model is enabled (`dbt run` builds it).

### Testing this one

```bash
dbt compile --profiles-dir . --select stg_customer_events
dbt run --profiles-dir . --select stg_customer_events
```

```python
import duckdb
con = duckdb.connect("dev.duckdb")

print(con.sql("SELECT COUNT(*) FROM stg_customer_events").fetchone()[0])   # 55

con.sql("""
    SELECT customer_id, COUNT(*) FROM stg_customer_events
    WHERE is_orphan_customer GROUP BY 1 ORDER BY 1
""").show()   # 9991: 2, 9992: 2, 9993: 3

# nothing should currently fall into the 'unknown' fallback -- if it does,
# either the source data changed or the known-value sets above need updating
con.sql("""
    SELECT COUNT(*) FROM stg_customer_events
    WHERE device = 'unknown' OR event_type = 'unknown' OR ip_country = 'unknown'
""").show()   # should be 0
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

Together these two sources are what the **reconciliation-rules** model
(`dim_customers_reconciled`, Module 10) resolves into a single customer
identity, and the exact-duplicate rows are what the **checksum**-based
dedup step (Module 7) collapses.

**`orders`**
- Keyed only to CRM `customer_id`. Deliberately has no `region` column —
  regional analysis requires joining through the customer dimension, which
  is the point: it forces the reconciliation work to matter downstream, not
  just as an academic exercise. `dim_customers_reconciled` (Module 10) now
  provides a `resolved_region`, and `daily_sales_summary` (Module 1) joins
  through it via its `target_region` param.

**`data/raw_json/events_*.json`**
- One file per day, array of event objects with a nested `metadata` object
  (`device`, `ip_country`) — flattened, validated, and enriched in
  `stg_customer_events.sql` via DuckDB's `read_json_auto` (Module 12).
- A handful of events reference `customer_id` 9991-9993, which don't exist
  in `crm_customers` — orphan records, flagged via `is_orphan_customer`
  rather than dropped or quarantined separately.

## Roadmap (fill in as each module is covered)

| Module concept | Status | Where it'll land |
|---|---|---|
| Parameterized models (Module 1) | done | `models/marts/daily_sales_summary.sql` + `vars:` in `dbt_project.yml` |
| Env/config-driven generation (Module 4) | done | `profiles.yml` (dev/prod targets) + `dbt_project.yml` (target-conditioned vars) |
| Checksums (Module 7) | done | `models/cleansing/dedup_ecommerce_customers.sql` |
| SCD2 (Module 8) | done | `models/history/dim_crm_customers_scd2.sql` |
| Reconciliation rules (Module 10) | done | `models/marts/dim_customers_reconciled.sql` |
| Batch JSON transformation (Module 12) | done | `models/staging/stg_customer_events.sql` |

## TODO checklist per module (not yet done)

Each item below is expanded in more detail as inline TODOs in the file
listed — this is just the quick-scan version.

**Module 7 — checksums** (`models/cleansing/dedup_ecommerce_customers.sql`) — done, see Module 7 section above
- [x] Pick the columns that define row identity for hashing.
- [x] Compute a checksum/hash column per row.
- [x] Dedup on the checksum; verify the row-count drop matches the known
      exact-duplicate count.
- [x] Enable the model.
- [x] Add a formal `schema.yml` `unique` test on the checksum — done, see
      `models/cleansing/schema.yml`.
- [x] Point Module 10 at it instead of `stg_ecommerce_customers` — done,
      see Module 10 section above.

**Module 8 — SCD2** (`models/history/dim_crm_customers_scd2.sql`) — done, see Module 8 section above
- [x] Sequence each `customer_id`'s versions by `updated_at`.
- [x] Derive `valid_from` / `valid_to` and an `is_current` flag.
- [x] Decide hand-rolled SQL vs. dbt's built-in snapshot feature (hand-rolled
      — see Module 8 section above for why).
- [x] Enable the model.
- [x] Add a formal test that each `customer_id` has exactly one
      `is_current = true` row — done, as a singular test (cross-row
      invariant, not a single-column property), see
      `tests/assert_one_current_row_per_crm_customer.sql`.
- [x] Point Module 10 at its current-row slice — done, see Module 10
      section above.

**Module 10 — reconciliation rules** (`models/marts/dim_customers_reconciled.sql`) — done, see Module 10 section above
- [x] Normalize email as the join key between CRM and ecommerce (already
      done upstream by both staging models — nothing extra needed here).
- [x] Write precedence rules for conflicting fields (region vs. country,
      name format, etc).
- [x] Emit one row per resolved customer at a consistent grain.
- [x] Read from `dedup_ecommerce_customers` (Module 7) and
      `dim_crm_customers_scd2` WHERE `is_current` (Module 8) rather than the
      raw staging models.
- [x] Normalize CRM's ALL-CAPS name casing (e.g. `PRIYA IVANOV`) via a
      hand-rolled title-case pass (no `initcap()` in this DuckDB version).
- [x] Revisit `daily_sales_summary` (Module 1) and add a real `target_region`
      param via a join through this table — done, see Module 1 section
      above.

**Module 12 continued — batch JSON validation/enrichment** (`models/staging/stg_customer_events.sql`) — done, see Module 12 section above
- [x] Decide how to surface the 9991-9993 orphan events — a flag column
      (`is_orphan_customer`), not a separate quarantine model.
- [x] Validate `metadata.device` / `metadata.ip_country` — `device`
      normalized against a known set with an `'unknown'` fallback;
      `ip_country` null/blank-guarded only (no fixed enum).
- [x] Normalize `event_type` — same known-set + `'unknown'`-fallback
      pattern as `device`.

All four planned modules (7, 8, 10, 12) are now done — nothing left on
this checklist.
