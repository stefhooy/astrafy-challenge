-- Rolls sales lines up to order grain. qty_product = total product quantity in the order
-- (SUM of qty across lines), per Exercise 4's definition of "the quantity of products in
-- the order".

select
    order_id,
    sum(qty) as qty_product

from {{ ref('stg_sales') }}
group by order_id
