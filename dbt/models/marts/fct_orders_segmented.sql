-- Exercise 6: 1 row per order, for var('segmentation_mart_year') (default 2026) only, with
-- order_segmentation added.

{{
    config(
        materialized='table',
        partition_by={'field': 'order_date', 'data_type': 'date'},
        cluster_by=['order_segmentation', 'customer_id']
    )
}}

select
    order_id,
    customer_id,
    order_date,
    net_sales,
    order_segment as order_segmentation

from {{ ref('int_orders_enriched') }}
where extract(year from order_date) = {{ var('segmentation_mart_year') }}
