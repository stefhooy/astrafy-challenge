# Exercises 1-6: Queries, Models & Results

## Exercises 1-3: queries & results

Both sections query the same table, `fct_orders` (Exercise 4's mart), and return identical
results. The dbt version runs through the project's `ref()` graph, the BigQuery version is
the same query run directly against the materialized table in BigQuery Studio, as a second,
independent confirmation of the numbers.

### dbt (`dbt show --inline`)

#### Exercise 1: number of orders in 2026

```powershell
dbt show --inline "select count(*) as order_count_2026 from {{ ref('fct_orders') }} where extract(year from order_date) = 2026"
```

| order_count_2026 |
| --- |
| 2573 |

#### Exercise 2: number of orders per month in 2026

```powershell
dbt show --inline "select extract(month from order_date) as month, count(*) as order_count from {{ ref('fct_orders') }} where extract(year from order_date) = 2026 group by 1 order by 1" --limit 20
```

| month | order_count |
| --- | --- |
| 1 | 232 |
| 2 | 176 |
| 3 | 203 |
| 4 | 188 |
| 5 | 172 |
| 6 | 169 |
| 7 | 193 |
| 8 | 167 |
| 9 | 212 |
| 10 | 223 |
| 11 | 389 |
| 12 | 249 |

#### Exercise 3: average number of products per order, per month, 2026

```powershell
dbt show --inline "select extract(month from order_date) as month, round(avg(qty_product), 2) as avg_qty_product from {{ ref('fct_orders') }} where extract(year from order_date) = 2026 group by 1 order by 1" --limit 20
```

| month | avg_qty_product |
| --- | --- |
| 1 | 12.57 |
| 2 | 12.62 |
| 3 | 13.07 |
| 4 | 15.10 |
| 5 | 14.63 |
| 6 | 14.18 |
| 7 | 13.75 |
| 8 | 14.46 |
| 9 | 13.67 |
| 10 | 13.03 |
| 11 | 10.48 |
| 12 | 11.37 |

### BigQuery SQL (BigQuery Studio)

Same three questions, run directly against the materialized table. Filters on `order_date`
using a date range (`BETWEEN`) rather than `EXTRACT(YEAR FROM ...)`, so BigQuery can prune
partitions on the `WHERE` clause (`fct_orders` is partitioned by `order_date`). Month grouping
uses `FORMAT_DATE('%Y-%m', order_date)` for a human-readable, unambiguous label.

#### Exercise 1: number of orders in 2026

```sql
SELECT count(*) as order_count_2026
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders`
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
```

| order_count_2026 |
| --- |
| 2573 |

#### Exercise 2: number of orders per month in 2026

```sql
SELECT
    FORMAT_DATE('%Y-%m', order_date) AS month,
    COUNT(*) AS order_count
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders`
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
GROUP BY 1
ORDER BY 1
```

| month | order_count |
| --- | --- |
| 2026-01 | 232 |
| 2026-02 | 176 |
| 2026-03 | 203 |
| 2026-04 | 188 |
| 2026-05 | 172 |
| 2026-06 | 169 |
| 2026-07 | 193 |
| 2026-08 | 167 |
| 2026-09 | 212 |
| 2026-10 | 223 |
| 2026-11 | 389 |
| 2026-12 | 249 |

#### Exercise 3: average number of products per order, per month, 2026

```sql
SELECT
    FORMAT_DATE('%Y-%m', order_date) AS month,
    ROUND(AVG(qty_product), 2) AS avg_qty_product
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders`
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
GROUP BY 1
ORDER BY 1
```

| month | avg_qty_product |
| --- | --- |
| 2026-01 | 12.57 |
| 2026-02 | 12.62 |
| 2026-03 | 13.07 |
| 2026-04 | 15.10 |
| 2026-05 | 14.63 |
| 2026-06 | 14.18 |
| 2026-07 | 13.75 |
| 2026-08 | 14.46 |
| 2026-09 | 13.67 |
| 2026-10 | 13.03 |
| 2026-11 | 10.48 |
| 2026-12 | 11.37 |

### Observation

November has by far the highest order count (389, ~85% above the monthly average of ~215) but
the *lowest* average products per order (10.48), consistent with a Black Friday / holiday
promotional effect: many more orders, but each smaller. Worth calling out as a real insight the
pipeline surfaces, not just numbers for their own sake.

## Exercise 4: orders table (2025+2026) with qty_product

Model: `models/marts/fct_orders.sql`. Filters `int_orders_enriched` to
`var('orders_mart_years')` (default `[2025, 2026]`), keeping the same shape as the source
`orders` table plus `qty_product`.

```powershell
dbt show --select fct_orders --limit 5
```

| order_id | customer_id | order_date | net_sales | qty_product |
| --- | --- | --- | --- | --- |
| 5068383 | 77973 | 2026-11-12 | 15.73 | 4 |
| 4000725 | 146283 | 2025-12-02 | 95.58 | 14 |
| 4589789 | 146283 | 2026-07-04 | 148.25 | 6 |
| 4996749 | 174933 | 2026-11-05 | 85.87 | 6 |
| 4563493 | 199083 | 2026-06-25 | 82.45 | 25 |

**Row count check**: confirms both years are present and the totals match the source data
exactly (1,088 orders in 2025 + 2,573 in 2026 = 3,661, the full order count):

```powershell
dbt show --inline "select extract(year from order_date) as year, count(*) as order_count from {{ ref('fct_orders') }} group by 1 order by 1"
```

| year | order_count |
| --- | --- |
| 2025 | 1088 |
| 2026 | 2573 |

`unique` and `not_null` tests on `order_id` pass, genuinely 1 row per order.

**BigQuery SQL cross-check** (same row count by year, run directly in Studio):

```sql
SELECT
    EXTRACT(YEAR FROM order_date) AS year,
    COUNT(*) AS order_count
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders`
GROUP BY 1
ORDER BY 1
```

| year | order_count |
| --- | --- |
| 2025 | 1088 |
| 2026 | 2573 |

Matches the dbt result exactly.

## Exercise 5: order segmentation logic

Rule: for each order, count that customer's orders placed strictly within the 365 days before
it (not including the order itself), then bucket:

| Prior orders in trailing 12mo | Segment |
| --- | --- |
| 0 | New |
| 1-3 | Returning |
| 4+ | VIP |

Maps directly to the brief's own wording:

| Brief's wording | Count | Label |
| --- | --- | --- |
| "did not place any orders" in the prior 12 months | 0 | New |
| "had already placed between 1 and 3 orders" | 1-3 | Returning |
| "had already placed at least 4 orders or more" | 4+ | VIP |

**This is purely a frequency count, not a value-weighted score.** Only the *number* of prior
orders is considered, never their monetary value, product mix, or spacing. A customer with
three small orders and a customer with three large orders in the same trailing window get the
identical segment. This deliberately matches the brief's own definition, which only uses
ordinal/count language ("1st order," "2nd-4th order," "5th or more"), never mentions spend.
Worth contrasting explicitly with the more common real-world RFM model (Recency, Frequency,
Monetary), which would also weigh recency and spend, that's a different, unasked question,
not a more thorough answer to this one.

**This is an order-level label, not a customer-level one.** The brief asks for "the segment
of this order," so the same customer can carry different segments on different orders over
time (New on their first order, Returning later, possibly VIP eventually), never a single
permanent label per customer. The count driving it is specifically "this customer's orders in
the 365 days *before this particular order*," not their lifetime order count.

Implemented in `models/intermediate/int_orders_enriched.sql` via a windowed count (see the
design spec / interview prep notes for the full `RANGE BETWEEN` / `UNIX_DATE` explanation),
computed over **all** order history so a 2026 order's window correctly reaches back into 2025
data, then labeled by `macros/segment_from_order_count.sql`, with the thresholds (1, 4) as
`vars` in `dbt_project.yml`, not hardcoded.

The count (`models/intermediate/int_orders_enriched.sql`):

```sql
count(*) over (
    partition by customer_id
    order by unix_date(order_date)
    range between 365 preceding and 1 preceding
) as prior_orders_last_12mo
```

The label (`macros/segment_from_order_count.sql`):

```sql
case
    when prior_orders_last_12mo >= {{ var('vip_order_threshold') }} then 'VIP'
    when prior_orders_last_12mo >= {{ var('returning_order_threshold') }} then 'Returning'
    else 'New'
end
```

**Concrete proof this actually uses cross-year history**: customer `146283` placed 5 orders
between September 2025 and November 2026. Querying `int_orders_enriched` directly (which holds
`order_segment` for all history, not just 2026: `fct_orders_segmented` only exposes the 2026
rows) shows the full progression:

```sql
SELECT order_id, order_date, prior_orders_last_12mo, order_segment
FROM `astrafy-challenge-509412.dbt_dev_intermediate.int_orders_enriched`
WHERE customer_id = 146283
ORDER BY order_date
```

| order_date | prior_orders_last_12mo | order_segment |
| --- | --- | --- |
| 2025-09-23 | 0 | New |
| 2025-12-02 | 1 | Returning |
| 2026-04-28 | 2 | Returning |
| 2026-07-04 | 3 | Returning |
| 2026-11-12 | 3 | Returning |

Worth walking through by hand once, since it's the trickiest logic in the pipeline:

- **2025-09-23**: no prior orders at all -> 0 -> New.
- **2025-12-02**: only the Sep order falls in the preceding 365 days -> 1 -> Returning.
- **2026-04-28**: both the Sep and Dec 2025 orders are still within the trailing 365 days
  (its window reaches back to 2025-04-28) -> 2 -> Returning. This is the first order whose
  segment is only correct *because* the window looks across the year boundary into 2025 data.
- **2026-07-04**: the Sep 2025, Dec 2025, and Apr 2026 orders are all still within the
  trailing 365 days (window reaches back to 2025-07-04) -> 3 -> Returning, not VIP.
- **2026-11-12**: the window has moved forward enough that the original 2025-09-23 order has
  now aged out (it's more than 365 days before this order), but the Dec 2025, Apr 2026, and
  Jul 2026 orders are all still within range -> 3, not 4 -> stays Returning rather than
  ticking over to VIP.

That last point is exactly why this customer never reaches VIP despite ordering fairly
consistently over 14 months: VIP requires 4+ orders within *any single* trailing 365-day
window, and this customer's cadence (roughly one order every 2-4 months) never quite clusters
five orders into one year-long window. That's the segmentation rule doing real, non-trivial
work, not just a threshold on lifetime order count.

This worked example isn't just a manual sanity check, it's also encoded as an automated
regression test: `dbt/tests/assert_segmentation_matches_known_customer_history.sql` asserts
this exact customer's full segment sequence programmatically, on every `dbt build`. The
generic `accepted_values` test only guarantees `order_segment` is one of the three allowed
strings; this singular test guarantees it's the *correct* one, for a case with a known,
hand-verified right answer, catching a future regression in the windowing logic or the
thresholds that `accepted_values` alone never would.

## Exercise 6: 2026 orders table with order_segmentation

Model: `models/marts/fct_orders_segmented.sql`. Filters `int_orders_enriched` to
`var('segmentation_mart_year')` (default `2026`), keeping the orders shape plus
`order_segmentation`.

```powershell
dbt show --select fct_orders_segmented --limit 5
```

| order_id | customer_id | order_date | net_sales | order_segmentation |
| --- | --- | --- | --- | --- |
| 5068383 | 77973 | 2026-11-12 | 15.73 | New |
| 4589789 | 146283 | 2026-07-04 | 148.25 | Returning |
| 4996749 | 174933 | 2026-11-05 | 85.87 | New |
| 4563493 | 199083 | 2026-06-25 | 82.45 | New |
| 4572402 | 238443 | 2026-06-28 | 67.24 | New |

**Segment distribution across all 2026 orders** (sums to 2,573, the exact 2026 order count;
every order gets exactly one segment):

```powershell
dbt show --inline "select order_segmentation, count(*) as n from {{ ref('fct_orders_segmented') }} group by 1 order by 1"
```

| order_segmentation | n |
| --- | --- |
| New | 1087 |
| Returning | 794 |
| VIP | 692 |

`unique`/`not_null` on `order_id`, and `accepted_values` restricting `order_segmentation` to
exactly `New`/`Returning`/`VIP`, all pass.

**BigQuery SQL cross-check** (same segment distribution, run directly in Studio):

```sql
SELECT
    order_segmentation,
    COUNT(*) AS n
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders_segmented`
GROUP BY 1
ORDER BY 1
```

| order_segmentation | n |
| --- | --- |
| New | 1087 |
| Returning | 794 |
| VIP | 692 |

Matches the dbt result exactly.
