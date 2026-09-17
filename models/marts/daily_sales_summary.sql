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
  high_value_threshold : numeric, default 300. Dollar amount used by
                         high_value_sales as the "big-ticket order" cutoff.

  CONDITIONAL COLUMN
  ---------------------------------------------------------
  high_value_sales : Only present in the output when target_category !=
                      'All'. Sum of total_amount for orders over
                      high_value_threshold, within the same date/status/
                      category filters as the rest of the row. Absent (not
                      null -- the column itself doesn't exist) when
                      target_category = 'All', since it's only meaningful
                      once you've drilled into a single category.

  WHY category INSTEAD OF region
  ---------------------------------------------------------
  The original course exercise parameterizes on region. This capstone's
  `orders` seed deliberately has no region column -- region only lives on
  the messy, unreconciled `crm_customers` side (see README "Known issues"),
  and joining through it now would fan out rows for the ~15% of customers
  with duplicate CRM records. product_category stands in as the drill-down
  dimension until the Module 10 reconciliation work makes a real regional
  join meaningful.
*/

{% set start_date = modules.datetime.datetime.strptime(var('analysis_date'), '%Y-%m-%d').date() %}
{% set end_date = start_date + modules.datetime.timedelta(days=(var('date_range_days', 1) | int) - 1) %}

SELECT
    order_date,
    product_category,
    COUNT(*)              AS order_count,
    SUM(total_amount)     AS total_sales,
    AVG(total_amount)     AS avg_order_value
    {% if var('target_category') != 'All' %}
    , SUM(CASE WHEN total_amount > {{ var('high_value_threshold', 300) }} THEN total_amount ELSE 0 END) AS high_value_sales
    {% endif %}
FROM {{ ref('stg_orders') }}
WHERE order_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
  AND status = '{{ var('order_status') }}'
  {% if var('target_category') != 'All' %}
  AND product_category = '{{ var('target_category') }}'
  {% endif %}
GROUP BY order_date, product_category
{% if target.name == 'dev' %}
LIMIT 100 -- keep local dev runs fast/cheap
{% endif %}
