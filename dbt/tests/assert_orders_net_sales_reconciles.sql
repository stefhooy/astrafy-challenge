-- Fails if any order's net_sales doesn't match the sum of its sales line items.
-- A small epsilon guards against harmless floating-point noise from the FLOAT64 -> NUMERIC
-- cast, not against real discrepancies.

with sales_agg as (
    select
        order_id,
        sum(net_sales) as summed_net_sales
    from {{ ref('stg_sales') }}
    group by order_id
)

select
    o.order_id,
    o.net_sales as order_net_sales,
    s.summed_net_sales,
    abs(o.net_sales - s.summed_net_sales) as diff
from {{ ref('stg_orders') }} o
inner join sales_agg s on o.order_id = s.order_id
where abs(o.net_sales - s.summed_net_sales) > 0.01
