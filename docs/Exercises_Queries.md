# Exercises 1-3 — Queries & Results

Both sections query the same table, `fct_orders` (Exercise 4's mart), and return identical
results — the dbt version runs through the project's `ref()` graph, the BigQuery version is
the same query run directly against the materialized table in BigQuery Studio, as a second,
independent confirmation of the numbers.

## dbt (`dbt show --inline`)

### Exercise 1 — number of orders in 2026

```powershell
dbt show --inline "select count(*) as order_count_2026 from {{ ref('fct_orders') }} where extract(year from order_date) = 2026"
```

| order_count_2026 |
| ----------------- |
| 2573 |

### Exercise 2 — number of orders per month in 2026

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

### Exercise 3 — average number of products per order, per month, 2026

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

## BigQuery SQL (BigQuery Studio)

Same three questions, run directly against the materialized table. Filters on `order_date`
using a date range (`BETWEEN`) rather than `EXTRACT(YEAR FROM ...)`, so BigQuery can prune
partitions on the `WHERE` clause — `fct_orders` is partitioned by `order_date`. Month grouping
uses `FORMAT_DATE('%Y-%m', order_date)` for a human-readable, unambiguous label.

### Exercise 1 — number of orders in 2026

```sql
SELECT count(*) as order_count_2026
FROM `astrafy-challenge-509412.dbt_dev_marts.fct_orders`
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
```

| order_count_2026 |
| ----------------- |
| 2573 |

### Exercise 2 — number of orders per month in 2026

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
| ------- | ------------ |
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

### Exercise 3 — average number of products per order, per month, 2026

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
| ------- | ---------------- |
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

## Observation

November has by far the highest order count (389, ~85% above the monthly average of ~215) but
the *lowest* average products per order (10.48) -- consistent with a Black Friday / holiday
promotional effect: many more orders, but each smaller. Worth calling out as a real insight the
pipeline surfaces, not just numbers for their own sake.
