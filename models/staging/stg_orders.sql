SELECT
    order_id,
    customer_id,
    CAST(order_date AS DATE)   AS order_date,
    total_amount,
    status,
    product_category
FROM {{ ref('orders') }}
