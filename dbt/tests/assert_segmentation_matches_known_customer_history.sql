-- Regression/golden-record test for the segmentation LOGIC, not just its shape.
-- accepted_values (in _intermediate.yml / _marts.yml) only checks that order_segment is one
-- of the three allowed strings; it would still pass even if the wrong label were assigned to
-- the wrong order. This test checks correctness directly: customer 146283's real order
-- history was hand-verified against the rolling 365-day window by hand (see
-- docs/Exercises_Queries.md, Exercise 5), including the case where an order's window reaches
-- across the year boundary into 2025 data, and the case where an older order ages out of a
-- later window. If a future change to the window logic or the thresholds silently breaks the
-- segmentation, this is the test that would actually catch it.

with expected as (
    select * from unnest([
        struct(3811749 as order_id, 0 as expected_prior_orders, 'New' as expected_segment),
        struct(4000725, 1, 'Returning'),
        struct(4422586, 2, 'Returning'),
        struct(4589789, 3, 'Returning'),
        struct(5076405, 3, 'Returning')
    ])
),

actual as (
    select order_id, prior_orders_last_12mo, order_segment
    from {{ ref('int_orders_enriched') }}
    where customer_id = 146283
)

select
    e.order_id,
    e.expected_segment,
    a.order_segment as actual_segment,
    e.expected_prior_orders,
    a.prior_orders_last_12mo as actual_prior_orders

from expected e
left join actual a on e.order_id = a.order_id
where a.order_id is null
   or a.order_segment != e.expected_segment
   or a.prior_orders_last_12mo != e.expected_prior_orders
