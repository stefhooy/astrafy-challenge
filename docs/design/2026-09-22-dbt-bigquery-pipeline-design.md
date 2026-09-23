# Astrafy Take-Home Part 1 (Coding Challenge): Design

## Scope
Part 1 only (confirmed by the recruiter): a dbt + BigQuery pipeline for
`orders_recrutement.xlsx` and `sales_recrutement.xlsx`. Parts 2 (LookML) and 3 (dashboard
design) are explicitly out of scope for this repo.

## Data recap
- `orders`: 3,661 rows, 1 row/order: `date_date, customers_id, orders_id, net_sales`
- `sales`: 28,361 rows, 1 row/order-product: `date_date, customer_id, order_id, products_id, net_sales, qty`
- Real date range: 2025-07-09 → 2026-12-31 (2,573 orders in 2026, 1,088 in 2025). The brief's
  "2022-2023" text is generic boilerplate; the exercises' "2026" is correct for this data.
- Data quality: no nulls, no duplicate order ids, `orders.net_sales` reconciles exactly with
  `SUM(sales.net_sales)` per order (max diff ~1e-12, floating point noise). One orphan:
  `order_id 5361303` appears in `sales` but not in `orders` (2026-12-31, customer 1382673),
  documented and tested as a known exception rather than silently dropped or left to fail a
  test without explanation.
- Column-naming inconsistency between the two source files (`customers_id` vs `customer_id`,
  `orders_id` vs `order_id`) is resolved in the staging layer, not carried downstream.

## Data loading strategy: raw BigQuery tables + dbt sources (not seeds)
dbt's own guidance is that seeds are for static reference data, not transactional fact data,
even at small volume. Using sources instead mirrors how data actually lands via a real EL tool,
which is the more defensible "production-ready" choice here.
- One-off Python script (`scripts/load_raw_data.py`) using `google-cloud-bigquery`
  (service-account JSON key auth, no `gcloud`/`bq` CLI required) loads the two Excel files into
  `raw.orders` and `raw.sales` in BigQuery.
- dbt `source.yml` declares `raw.orders` / `raw.sales` with column descriptions.

## Model layers

```
sources: raw.orders, raw.sales
        │
staging/
  stg_orders   -- rename/cast; canonical column names; 1 row per order
  stg_sales    -- rename/cast; canonical column names; 1 row per order-product line
        │
intermediate/
  int_orders_products_agg  -- sales rolled up to order grain (qty_product = SUM(qty), line count, net_sales recon)
  int_orders_enriched      -- stg_orders + int_orders_products_agg + rolling-12mo order
                                sequence/segmentation, computed over ALL order history
                                (2026 orders' trailing-12mo window reaches back into 2025 data)
        │
marts/
  fct_orders            -- Ex4: orders for {{ var('orders_mart_years') }} (default [2025, 2026])
                             with qty_product added
  fct_orders_segmented  -- Ex6: orders for {{ var('segmentation_mart_year') }} (default 2026)
                             with order_segmentation added
```

Year boundaries are dbt `vars` (defaults in `dbt_project.yml`), not hardcoded literals in SQL.

## Segmentation logic (Ex5)
For each order: count that customer's orders strictly within the prior 365 days.
- 0 prior orders → **New**
- 1-3 prior orders → **Returning**
- 4+ prior orders → **VIP**

BigQuery detail: window `RANGE BETWEEN` frames require a numeric ORDER BY expression. `DATE`
isn't directly usable. Idiomatic/efficient pattern: order by `UNIX_DATE(order_date)`,
`RANGE BETWEEN 365 PRECEDING AND 1 PRECEDING`, partitioned by `customer_id`. This avoids a
self-join and lets BigQuery execute it as a single windowed pass, which matters at the
"billions of rows" scale the brief asks us to design for.

Thresholds (1, 4) and labels are centralized in a macro (`segment_from_order_count(count_col)`)
driven by `vars`, not repeated/magic-numbered across models.

## Exercises 1-3: no dedicated models
Building a persisted dbt model per ad-hoc question would be a non-reusable, non-DRY one-off.
Instead: documented SQL queries against `fct_orders` / `fct_orders_segmented`, with the exact
SQL and the resulting numbers written into the README. This mirrors how a BI/semantic layer
would actually compute these on demand.

## Testing
- Generic (schema.yml): `unique`/`not_null` on order ids, `relationships` between sales and
  orders **in both directions** (sales -> orders at `warn` severity, since the one known
  orphan `order_id 5361303` is a documented, accepted exception rather than a bug; orders ->
  sales at normal `error` severity, since that direction has zero known exceptions),
  `accepted_values` on `order_segmentation` (`New`/`Returning`/`VIP`), and
  `dbt_utils.expression_is_true` asserting non-negative `net_sales`/`qty` (added after an
  audit found `dbt_utils` was installed but unused).
- Singular test: reconciliation (`SUM(sales.net_sales)` per order equals `orders.net_sales`).

Final count: 42 dbt tests, all passing against real BigQuery data (see `docs/LOG.md` for the
full history of what was added and why).

## Performance / BigQuery best practices

- `fct_orders` / `fct_orders_segmented`: table materialization, partitioned by `order_date`
  (daily), clustered by `customer_id`, designed for scan-cost efficiency at scale even though
  actual volume here is ~30k rows.
- `stg_*`: views. `int_*`: tables (the rolling-window computation is reused by multiple marts,
  worth materializing once rather than recomputing per mart).
- Schema naming uses dbt's **default** `generate_schema_name` behavior (no custom macro
  needed): `+schema:` config per layer in `dbt_project.yml` combines with the target's base
  schema to produce `<target_schema>_staging` / `_intermediate` / `_marts` automatically.

## Tooling / environment
1. `pip install dbt-core dbt-bigquery` in a project-local venv.
2. GCP: existing Google Cloud account; a project with the BigQuery API enabled and a service
   account (BigQuery Data Editor + Job User roles) with a downloaded JSON key. No `gcloud` CLI
   install required. Key-file auth is sufficient for `dbt-bigquery`.
3. `profiles.yml` configured for keyfile-based auth pointing at that JSON key, kept out of git.
4. VS Code is the editor; dbt itself runs via terminal (`dbt run`, `dbt test`, `dbt build`).

## Repo layout (as built)

A point-in-time snapshot from the design phase, kept for historical context: see README.md's
own "Repo layout" section for the always-current version.

```
astrafy-challenge/
  data/                       -- raw xlsx source files (tracked; brief .docx is gitignored)
  scripts/load_raw_data.py    -- one-off raw loader into BigQuery
  dbt/
    dbt_project.yml
    packages.yml              -- dbt_utils
    models/
      staging/
      intermediate/
      marts/
    macros/
    tests/
  docs/
    design/                   -- design docs (this file)
    SETUP.md                  -- BigQuery + dbt environment setup (includes the profiles.yml
                                  YAML directly, rather than a separate .example file)
    Exercises_Queries.md      -- all 6 exercise answers
    LOG.md                    -- running build log
  .github/workflows/          -- CI (dbt build) and docs-site publishing
  README.md
```

## Status
- [x] Design approved in conversation
- [x] GCP project + service account key ready
- [x] dbt project scaffolded
- [x] Raw data loaded to BigQuery
- [x] Staging/intermediate/marts built
- [x] Tests passing (42/42, locally and in CI)
- [x] Exercises 1-6 answered and documented in `docs/Exercises_Queries.md`
- [x] README finalized
- [x] CI added (`.github/workflows/dbt_build.yml`)
- [x] Live docs/lineage site published (`.github/workflows/dbt_docs.yml`,
      `stefhooy.github.io/astrafy-challenge`)
- [x] Self-audit pass: closed real gaps (unused `dbt_utils` dependency, missing bidirectional
      test, no CI): see `docs/LOG.md` (2026-09-23 entries) for the full account

Part 1 is complete. This document is kept as-is for its original purpose (the reasoning
behind decisions made *before* implementation began), rather than rewritten to read as if it
were written after the fact. See `docs/LOG.md` for what actually happened during the build,
including where reality diverged from this plan (e.g. `FLOAT64` vs `NUMERIC` at the raw layer,
discovered only once implementation started).
