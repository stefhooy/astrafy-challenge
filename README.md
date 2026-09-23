# Astrafy Take-Home Challenge — Part 1: Coding Challenge

dbt + BigQuery pipeline for the Astrafy analytics engineering take-home challenge (Part 1 only,
per recruiter guidance — Parts 2 and 3 of the original brief are out of scope for this repo).

## What this is

Two source extracts — `orders` (3,661 rows, 1 row per order) and `sales` (28,361 rows, 1 row
per order/product line), covering 2025-07-09 through 2026-12-31 — transformed through a
staging → intermediate → marts dbt pipeline into BigQuery, answering the 6 exercises below.

| Exercise | Deliverable | Result |
| --- | --- | --- |
| Ex1: orders in 2026 | Query against `fct_orders` | **2,573** |
| Ex2: orders per month, 2026 | Query against `fct_orders` | see [Exercises_Queries.md](docs/Exercises_Queries.md) |
| Ex3: avg products/order per month, 2026 | Query against `fct_orders` | see [Exercises_Queries.md](docs/Exercises_Queries.md) |
| Ex4: orders table (2025+2026) + `qty_product` | `fct_orders` mart | 3,661 rows |
| Ex5: order segmentation logic (New/Returning/VIP) | Rolling-12mo logic in `int_orders_enriched` | see below |
| Ex6: 2026 orders table + `order_segmentation` | `fct_orders_segmented` mart | 2,573 rows |

Ex1–3 are answered as documented SQL queries against the marts rather than as separate
persisted models — see [Why Ex1-3 aren't separate models](#why-ex1-3-arent-separate-models)
below. Full queries, results, and a hand-verified worked example for the segmentation logic are
in [`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).

## Architecture

```text
raw.orders, raw.sales        <- loaded by scripts/load_raw_data.py (plain Python, not dbt),
        │                        an exact copy of the two source Excel files
        │
stg_orders, stg_sales        <- VIEWS. Rename/cast only: resolves the source files'
        │                        inconsistent column naming (customers_id/customer_id,
        │                        orders_id/order_id), casts net_sales FLOAT64 -> NUMERIC.
        │                        No business logic here.
        │
int_orders_products_agg      <- TABLE. One row per order: qty_product = SUM(qty) across
        │                        that order's sales lines.
int_orders_enriched          <- TABLE. Orders + qty_product + order_segment, computed via
        │                        a rolling 365-day windowed count of each customer's prior
        │                        orders. Computed over ALL order history (not just 2026),
        │                        since a 2026 order's trailing-12-month window reaches back
        │                        into 2025 data.
        │
fct_orders                   <- TABLE. int_orders_enriched filtered to var('orders_mart_years')
        │                        (2025+2026). = Exercise 4. Partitioned by order_date,
        │                        clustered by customer_id.
fct_orders_segmented         <- TABLE. int_orders_enriched filtered to
                                 var('segmentation_mart_year') (2026). = Exercise 6.
                                 Partitioned by order_date, clustered by order_segmentation
                                 then customer_id.
```

Each layer is a dbt model calling `{{ ref(...) }}` on the previous one — dbt resolves the build
order from those references (a DAG), nothing is manually sequenced.

## Key architectural decisions

- **Raw BigQuery tables + dbt sources, not dbt seeds.** dbt's own guidance is that seeds are
  for small, static reference data, not transactional fact data, even at small volume. Loading
  via a one-off script into `raw.*` tables and reading them as sources mirrors how data
  actually lands from a real ingestion tool in production.
- **`FLOAT64` in raw, cast to `NUMERIC` in staging.** Raw tables mirror the source system
  exactly — they're not the place to clean data. Type normalization (money-safe precision)
  happens once, in staging, the single point everything downstream reads clean data from.
  (Also a practical workaround: `google-cloud-bigquery`'s `load_table_from_dataframe` can't
  convert a pandas `float64` column straight to `NUMERIC`.)
- **Segmentation computed over full history, not just 2026**, in `int_orders_enriched`, then
  filtered down to the exercise's target year only in the final mart. Otherwise a January 2026
  order would look like a brand-new customer's first order even if they'd ordered several times
  in late 2025 — the trailing-12-month window has to be able to see across the year boundary.
- **BigQuery-idiomatic rolling window, not a self-join.** BigQuery's `RANGE BETWEEN` window
  frame requires a numeric `ORDER BY` expression — `DATE` isn't accepted directly. The pattern
  used is `order by UNIX_DATE(order_date) range between 365 preceding and 1 preceding`,
  partitioned by `customer_id`: a single windowed pass per customer, no join, no row explosion.
  Matters at the "billions of rows" scale the brief asks us to design for. Full walkthrough,
  including a hand-verified worked example against a real customer's order history, in
  [`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).
- **Thresholds and labels centralized in a macro + vars**, not repeated/hardcoded SQL:
  `dbt/macros/segment_from_order_count.sql` reads `returning_order_threshold` /
  `vip_order_threshold` from `dbt/dbt_project.yml`. Year boundaries (`orders_mart_years`,
  `segmentation_mart_year`) are
  vars too — re-pointing either mart at a different period is a one-line change, not a
  code edit.
- **Partitioning and clustering on both marts**: partitioned by `order_date` (daily), clustered
  by `customer_id` (`fct_orders`) or `order_segmentation` then `customer_id`
  (`fct_orders_segmented`, since segment-filtered queries are the expected access pattern) —
  designed for scan-cost efficiency at scale, even though the actual data here is ~30k rows.

### Why Ex1-3 aren't separate models

Ex1–3 ("how many orders in 2026", "orders per month", "avg products per order per month") have
no independent existence as deliverables — they're aggregate questions answerable with a
`COUNT(*)`/`AVG()` against the `fct_orders` table Ex4 already produces. Building a dedicated,
persisted dbt model per ad-hoc question would be a non-reusable one-off that duplicates logic
already in the marts. Instead they're documented SQL queries, verified two ways (via
`dbt show` and via raw SQL run directly in BigQuery) in
[`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).

## Data quality notes

- No nulls in either source file; no duplicate `order_id`s in `orders`.
- `orders.net_sales` reconciles exactly with `SUM(sales.net_sales)` grouped by order — enforced
  by a singular test (`dbt/tests/assert_orders_net_sales_reconciles.sql`).
- One known orphan: `order_id 5361303` appears in `sales` but has no matching row in `orders`
  (2026-12-31, customer 1382673) — present in the raw source file itself, not introduced by
  this pipeline. Rather than silently dropping it or failing the *entire* build over one known
  row, the `relationships` generic test on `stg_sales.order_id` is configured at `warn`
  severity instead of `error`. This means: `dbt build` always surfaces it (visible in the run
  output as `WARN 1`, never silently swallowed), but doesn't block every future build over an
  unfixable row in someone else's source data. If a *new* orphan ever appeared, the warning
  count would increase and be just as visible; if this one were fixed upstream, the warning
  would disappear on its own — no dbt code change needed either way. See
  `dbt/models/staging/_staging.yml`.

## Documentation site

Live, browsable dbt docs (model/column descriptions, compiled SQL, and an interactive lineage
graph of the full staging → intermediate → marts DAG) are published at:

**[stefhooy.github.io/astrafy-challenge](https://stefhooy.github.io/astrafy-challenge/)**

Auto-generated and deployed via `.github/workflows/dbt_docs.yml` on every push. To generate and
browse it locally instead:

```bash
cd dbt
dbt docs generate
dbt docs serve
```

## Testing

42 dbt tests across staging/intermediate/marts, all passing against real BigQuery data:
generic tests (`unique`, `not_null`, `relationships` in both directions between orders and
sales, `accepted_values` on the segmentation labels, `dbt_utils.expression_is_true` asserting
non-negative `net_sales`/`qty`) plus the singular net_sales reconciliation test described
above.

```bash
dbt build   # runs all models + all tests, in dependency order
```

Also runs automatically in CI (`.github/workflows/dbt_build.yml`) on every push, against an
isolated `dbt_ci` target/dataset — see the repo's **Actions** tab.

## Repo layout

```text
data/                         -- raw source xlsx files
scripts/load_raw_data.py      -- one-off loader: xlsx -> raw BigQuery tables
dbt/
  dbt_project.yml             -- vars for year boundaries + segmentation thresholds
  packages.yml                -- dbt_utils
  models/
    staging/                  -- stg_orders, stg_sales + sources.yml
    intermediate/              -- int_orders_products_agg, int_orders_enriched
    marts/                     -- fct_orders (Ex4), fct_orders_segmented (Ex6)
  macros/segment_from_order_count.sql
  tests/assert_orders_net_sales_reconciles.sql
docs/
  superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md   -- full design rationale
  SETUP.md                     -- BigQuery + dbt environment setup, step by step
  Exercises_Queries.md         -- all 6 exercise answers: queries, results, worked examples
  LOG.md                       -- running build log
```

## Setup

Full step-by-step walkthrough (GCP project, service account, dbt install, `profiles.yml`) is
in [`docs/SETUP.md`](docs/SETUP.md). Short version:

1. Create a GCP project, enable the BigQuery API, create a service account with
   `BigQuery Data Editor` + `BigQuery Job User`, download its JSON key.
2. `uv venv && uv pip install dbt-core dbt-bigquery google-cloud-bigquery` (or any Python
   package manager).
3. Configure `~/.dbt/profiles.yml` with a `service-account` connection pointing at that key
   (see `docs/SETUP.md` for the exact YAML).
4. Load the raw data:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
   python scripts/load_raw_data.py --project <your-gcp-project-id>
   ```

5. Build and test everything:

   ```bash
   cd dbt
   dbt deps
   dbt build
   ```

## Further reading

- [Design spec](docs/superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md) — full
  architecture rationale, written before implementation began.
- [Exercises_Queries.md](docs/Exercises_Queries.md) — every exercise's answer, queries (dbt +
  raw BigQuery SQL), and a hand-verified worked example of the segmentation logic against a
  real customer's order history.
- [LOG.md](docs/LOG.md) — running log of the actual build process and decisions made along
  the way.
