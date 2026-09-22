-- Orders enriched with qty_product and order segmentation, computed over ALL order history
-- (not just the exercise years) so that a 2026 order's trailing-12-month window correctly
-- reaches back into 2025 order history. Marts filter this down to the years each exercise
-- actually needs.

with orders as (
    select * from {{ ref('stg_orders') }}
),

products_agg as (
    select * from {{ ref('int_orders_products_agg') }}
),

orders_with_products as (
    select
        o.order_id,
        o.customer_id,
        o.order_date,
        o.net_sales,
        coalesce(p.qty_product, 0) as qty_product

    from orders o
    left join products_agg p on o.order_id = p.order_id
),

-- Count of each customer's orders placed strictly within the 365 days before the current
-- order. BigQuery's RANGE frame requires a numeric ORDER BY expression, so we order by
-- unix_date(order_date) rather than the DATE itself -- this avoids a self-join and lets
-- BigQuery evaluate the whole thing as a single windowed pass, which matters at scale.
orders_with_prior_count as (
    select
        *,
        count(*) over (
            partition by customer_id
            order by unix_date(order_date)
            range between 365 preceding and 1 preceding
        ) as prior_orders_last_12mo

    from orders_with_products
)

select
    order_id,
    customer_id,
    order_date,
    net_sales,
    qty_product,
    prior_orders_last_12mo,
    {{ segment_from_order_count('prior_orders_last_12mo') }} as order_segment

from orders_with_prior_count
