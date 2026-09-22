with source as (
    select * from {{ source('raw', 'orders') }}
)

select
    orders_id                  as order_id,
    customers_id                as customer_id,
    date_date                   as order_date,
    cast(net_sales as numeric)  as net_sales

from source
