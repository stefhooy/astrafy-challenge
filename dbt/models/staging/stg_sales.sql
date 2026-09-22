with source as (
    select * from {{ source('raw', 'sales') }}
)

select
    order_id,
    customer_id,
    products_id                 as product_id,
    date_date                   as order_date,
    cast(net_sales as numeric)  as net_sales,
    qty

from source
