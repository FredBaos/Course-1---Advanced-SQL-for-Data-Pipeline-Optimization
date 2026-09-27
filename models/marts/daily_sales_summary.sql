/*
  Model: daily_sales_summary
  Concept: Build Your First Parameterized dbt Pipeline (Module 1)

  BUSINESS CONTEXT
  -----------------
  Replaces a report someone used to hand-edit every morning (today's date,
  a status, sometimes a category drill-down) with a dbt model that can
  process any date range / status / category combo via --vars, no code
  changes required.

  PARAMETER REFERENCE
  ---------------------------------------------------------
  analysis_date       : DATE string, e.g. '2024-01-13'. Start of the date
                         range to summarize (see date_range_days).
  date_range_days      : integer, default 1. Number of consecutive days,
                         starting at analysis_date, inclusive. analysis_date
                         = '2024-01-13' with date_range_days = 3 covers
                         2024-01-13 through 2024-01-15. Output has one row
                         per (order_date, product_category) in that window,
                         not one row overall.
  order_status         : e.g. 'completed', 'pending', 'cancelled'. Which
                         order status to include.
  target_category      : 'All' | 'Apparel' | 'Electronics' | 'Grocery' |
                         'Home' | 'Sporting Goods'. 'All' means no category
                         filter is applied. Any other value both filters to
                         that category AND turns on the high_value_sales
                         breakdown column (see below).
  target_region        : 'All' | 'North' | 'South' | 'East' | 'West' |
                         'USA' | 'Canada' | 'Mexico' (whatever
                         dim_customers_reconciled.resolved_region actually
                         contains). 'All' (default) means no regional join
                         happens at all -- same "absent, not just null"
                         pattern as target_category/high_value_sales below.
                         Any other value joins to dim_customers_reconciled
                         on customer_id, filters to that resolved_region,
                         and adds a resolved_region output column.
  high_value_threshold : numeric, default 300. Dollar amount used by
                         high_value_sales as the "big-ticket order" cutoff.

  CONDITIONAL COLUMNS
  ---------------------------------------------------------
  high_value_sales : Only present in the output when target_category !=
                      'All'. Sum of total_amount for orders over
                      high_value_threshold, within the same date/status/
                      category filters as the rest of the row. Absent (not
                      null -- the column itself doesn't exist) when
                      target_category = 'All', since it's only meaningful
                      once you've drilled into a single category.
  resolved_region  : Only present when target_region != 'All' -- same
                      "absent, not null" convention as high_value_sales.

  WHY category, AND NOW ALSO region
  ---------------------------------------------------------
  The original course exercise parameterizes on region. This capstone's
  `orders` seed deliberately has no region column -- region only lived on
  the messy, unreconciled `crm_customers` side (see README "Known issues"),
  and joining through it before Module 10 would have fanned out rows for
  the ~15% of customers with duplicate CRM records. product_category stood
  in as the drill-down dimension until Module 10's dim_customers_reconciled
  existed. Now that it does (customer_id -> resolved_region, one row per
  customer, no fan-out), target_region joins through it -- confirmed via
  dev.duckdb that every order's customer_id resolves to exactly one row in
  dim_customers_reconciled (220 orders in, 220 out), so the join never
  drops or duplicates a row. target_category remains the primary drill-down
  dimension; target_region is additive, not a replacement.
*/

{% set start_date = modules.datetime.datetime.strptime(var('analysis_date'), '%Y-%m-%d').date() %}
{% set end_date = start_date + modules.datetime.timedelta(days=(var('date_range_days', 1) | int) - 1) %}
{% set region_filter_active = var('target_region', 'All') != 'All' %}

SELECT
    o.order_date,
    o.product_category,
    {% if region_filter_active %}
    c.resolved_region,
    {% endif %}
    COUNT(*)              AS order_count,
    SUM(o.total_amount)   AS total_sales,
    AVG(o.total_amount)   AS avg_order_value
    {% if var('target_category') != 'All' %}
    , SUM(CASE WHEN o.total_amount > {{ var('high_value_threshold', 300) }} THEN o.total_amount ELSE 0 END) AS high_value_sales
    {% endif %}
FROM {{ ref('stg_orders') }} AS o
{% if region_filter_active %}
JOIN {{ ref('dim_customers_reconciled') }} AS c ON c.customer_id = o.customer_id
{% endif %}
WHERE o.order_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
  AND o.status = '{{ var('order_status') }}'
  {% if var('target_category') != 'All' %}
  AND o.product_category = '{{ var('target_category') }}'
  {% endif %}
  {% if region_filter_active %}
  AND c.resolved_region = '{{ var('target_region') }}'
  {% endif %}
GROUP BY o.order_date, o.product_category
{%- if region_filter_active %}, c.resolved_region{% endif %}
{% if target.name == 'dev' %}
LIMIT 100 -- keep local dev runs fast/cheap
{% endif %}
