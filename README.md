# Astrafy Take-Home Challenge — Part 1: Coding Challenge

dbt + BigQuery pipeline for the Astrafy analytics engineering take-home challenge (Part 1 only,
per recruiter guidance — Parts 2 and 3 of the original brief are out of scope for this repo).

## What this is

Two source extracts — `orders` (1 row per order) and `sales` (1 row per order/product line) —
covering 2025–2026 order history, transformed through a staging → intermediate → marts dbt
pipeline into BigQuery to answer the 6 exercises in Part 1 of the challenge:

| Exercise | Deliverable |
| --- | --- |
| Ex1: number of orders in 2026 | SQL query documented below against `fct_orders`, with result |
| Ex2: number of orders per month in 2026 | SQL query documented below against `fct_orders`, with result |
| Ex3: avg number of products per order, per month, 2026 | SQL query documented below against `fct_orders`, with result |
| Ex4: orders table (2025+2026) with `qty_product` added | `fct_orders` dbt mart |
| Ex5: order segmentation logic (New / Returning / VIP) | Rolling-12-month window logic in `int_orders_enriched`, centralized in a macro |
| Ex6: 2026 orders table with `order_segmentation` added | `fct_orders_segmented` dbt mart |

Ex1–3 are answered as queries against the marts rather than as separate persisted models —
see the design doc's "Exercises 1–3" section for the rationale.

## Status

🚧 In progress. Design is finalized — see
[`docs/superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md`](docs/superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md)
for the full architecture, modeling, testing, and performance rationale. Implementation
(dbt project scaffold, BigQuery loading, models, tests, exercise answers) is next.

## Repo layout

```text
data/                       -- raw source xlsx files
scripts/load_raw_data.py    -- one-off loader: xlsx -> raw BigQuery tables
dbt/                         -- dbt project (staging / intermediate / marts)
docs/                        -- design docs
```

## Setup

_To be filled in once the dbt project is scaffolded — will cover local dbt install, BigQuery
service-account auth, and how to run `dbt build`._

## Exercise answers

_To be filled in with the exact SQL and verified results for Exercises 1-3 once the marts are
built and tested against BigQuery._
