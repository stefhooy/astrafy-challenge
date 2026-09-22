-- Exercise 4: 1 row per order, for the years in var('orders_mart_years') (default 2025+2026),
-- with qty_product added.

{{
    config(
        materialized='table',
        partition_by={'field': 'order_date', 'data_type': 'date'},
        cluster_by=['customer_id']
    )
}}

select
    order_id,
    customer_id,
    order_date,
    net_sales,
    qty_product

from {{ ref('int_orders_enriched') }}
where extract(year from order_date) in ({{ var('orders_mart_years') | join(', ') }})
