# Astrafy Take-Home Challenge, Part 1: Coding Challenge

dbt + BigQuery pipeline for the Astrafy analytics engineering take-home challenge (Part 1 only,
per recruiter guidance: Parts 2 and 3 of the original brief are out of scope for this repo).

## What this is

Two source extracts: `orders` (3,661 rows, 1 row per order) and `sales` (28,361 rows, 1 row
per order/product line), covering 2025-07-09 through 2026-12-31. These are transformed through
a staging → intermediate → marts dbt pipeline into BigQuery, answering the 6 exercises below.

| Exercise | Deliverable | Result |
| --- | --- | --- |
| Ex1: orders in 2026 | Query against `fct_orders` | **2,573** |
| Ex2: orders per month, 2026 | Query against `fct_orders` | see [Exercises_Queries.md](docs/Exercises_Queries.md) |
| Ex3: avg products/order per month, 2026 | Query against `fct_orders` | see [Exercises_Queries.md](docs/Exercises_Queries.md) |
| Ex4: orders table (2025+2026) + `qty_product` | `fct_orders` mart | 3,661 rows |
| Ex5: order segmentation logic (New/Returning/VIP) | Rolling-12mo logic in `int_orders_enriched` | see below |
| Ex6: 2026 orders table + `order_segmentation` | `fct_orders_segmented` mart | 2,573 rows |

Ex1-3 are answered as documented SQL queries against the marts rather than as separate
persisted models. See [Why Ex1-3 aren't separate models](#why-ex1-3-arent-separate-models)
below. Full queries, results, and a hand-verified worked example for the segmentation logic are
in [`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).

## Architecture

```text
raw.orders, raw.sales        <- an exact copy of the two source Excel files, loaded by
        │                        scripts/load_raw_data.py (plain Python, not dbt)
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

Each layer is a dbt model calling `{{ ref(...) }}` on the previous one: dbt resolves the build
order from those references (a DAG), nothing is manually sequenced.

## Key architectural decisions

Each decision below follows the same pattern: what we did, then why, so it's clear these are
deliberate tradeoffs rather than arbitrary defaults.

**1. Raw BigQuery tables + dbt sources, not dbt seeds.**

- *What*: the two Excel files are loaded into BigQuery once via a Python script
  (`scripts/load_raw_data.py`), and dbt reads them as **sources** rather than loading them
  itself as **seeds**.
- *Why*: dbt's own guidance is that seeds are for small, static reference data, not real
  transactional data, even at small volume. Reading from sources also mirrors how data would
  actually arrive in a real company (via an ingestion tool), which is the more realistic,
  production-like setup.

**2. `FLOAT64` in raw, cast to `NUMERIC` in staging.**

- *What*: money values (`net_sales`) are stored as the imprecise `FLOAT64` type in the raw
  tables, then converted to the precise `NUMERIC` type in staging.
- *Why*: raw tables should be an exact mirror of the source, not a cleaned-up version. All
  type cleanup happens in exactly one place (staging), so every downstream model reads
  already-correct data. There's also a practical reason: the Python library used to load the
  data can't convert directly from `float64` to `NUMERIC`.

**3. Segmentation is calculated across all order history, not just 2026, then filtered down later.**

- *What*: the New/Returning/VIP logic runs against every order in the dataset (2025 and
  2026), inside `int_orders_enriched`. Only the final table is trimmed down to just the 2026
  rows the exercise asks for.
- *Why*: a January 2026 order's "trailing 12 months" reaches back into 2025. Filtering to
  2026 first would make a customer who'd ordered several times in late 2025 incorrectly look
  brand new.

**4. A rolling window calculation, not a self-join.**

- *What*: counting each customer's orders in their preceding 365 days uses a SQL window
  function (`RANGE BETWEEN ... PRECEDING`), not a join of the orders table against itself.
- *Why*: a self-join compares every row to every other row for the same customer, which gets
  expensive as the data grows. The window function computes the same result in a single
  pass, directly relevant to the brief's requirement to design with "billions of rows" in
  mind. Full explanation of this specific technique, including a hand-verified worked
  example against a real customer's order history, in
  [`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).

**5. Segmentation thresholds and mart year boundaries live in one place, not hardcoded.**

- *What*: the numbers that define New/Returning/VIP (1 and 4 prior orders) live in
  `dbt_project.yml` as variables, read by `macros/segment_from_order_count.sql`. The years
  each mart covers are variables too.
- *Why*: if the business rule ever changes (e.g. VIP becomes 5+ orders instead of 4+), it's a
  one-line change in one file, not a search-and-replace across multiple SQL files.

**6. The two output tables are partitioned and clustered.**

- *What*: `fct_orders` and `fct_orders_segmented` are partitioned by `order_date` and
  clustered by `customer_id` (or by `order_segmentation` first, for the segmented table).
- *Why*: this is a BigQuery-specific cost control. It lets a future query that filters by
  date or customer scan only the relevant slice of the table instead of the whole thing. It
  has almost no effect at this project's actual size (~30k rows), but it's exactly the kind
  of setting that matters once a table has billions of rows, the scale the brief asks us to
  design for.

### Why Ex1-3 aren't separate models

Ex1-3 ("how many orders in 2026", "orders per month", "avg products per order per month") have
no independent existence as deliverables: they're aggregate questions answerable with a
`COUNT(*)`/`AVG()` against the `fct_orders` table Ex4 already produces. Building a dedicated,
persisted dbt model per ad-hoc question would be a non-reusable one-off that duplicates logic
already in the marts. Instead they're documented SQL queries, verified two ways (via
`dbt show` and via raw SQL run directly in BigQuery) in
[`docs/Exercises_Queries.md`](docs/Exercises_Queries.md).

## Data quality notes

**1. No nulls, no duplicate order IDs.**

- *What*: confirmed directly in both source files, and enforced going forward by
  `not_null`/`unique` tests on every key column.
- *Why*: the most basic possible sanity check. If this failed, nothing built on top of it
  could be trusted.

**2. Order totals reconcile exactly with their sales lines.**

- *What*: `orders.net_sales` matches `SUM(sales.net_sales)` for every single order, enforced
  by a singular test (`dbt/tests/assert_orders_net_sales_reconciles.sql`).
- *Why*: this is the strongest available check that the two source files actually agree with
  each other, not just that each one looks valid in isolation.

**3. One known "orphan" order, deliberately a warning, not an error.**

- *What*: `order_id 5361303` appears in `sales` but has no matching row in `orders`
  (2026-12-31, customer 1382673), present in the raw source file itself, not introduced by
  this pipeline. The `relationships` test that checks this is configured at `warn` severity
  instead of `error`. See `dbt/models/staging/_staging.yml`.
- *Why*: a hard error would fail the *entire* build, every single time, over one row in
  someone else's data that can't be fixed from here. `warn` keeps it visible in every run
  (`WARN 1` in the output, never silently swallowed) without blocking everything else. If a
  *new* orphan ever appeared, the warning count would increase and be just as visible; if
  this one were fixed upstream, the warning would disappear on its own, no code change needed
  either way.

**4. A known limitation in the segmentation logic, not a bug.**

- *What*: the dataset only starts 2025-07-09, so orders placed early in that window can be
  undercounted as "New" relative to a customer's true, unobserved, pre-extract order history.
- *Why*: this is a boundary of the data extract itself, not something the pipeline computes
  incorrectly. Worth stating explicitly rather than leaving it as a silent blind spot; it
  self-corrects over time as more history accumulates within the dataset.

## What the .yml files are for

dbt splits two different things into two different file types. **SQL files** hold the actual
transformation logic (the `SELECT` that produces a table). **YAML files** hold everything
*about* that SQL: descriptions, column documentation, tests, and configuration. Every folder
under `dbt/models/` has an underscore-prefixed `.yml` file (`_sources.yml`, `_staging.yml`,
`_intermediate.yml`, `_marts.yml`) alongside its `.sql` model files.

- *What*: each model's `.yml` file lists its columns, a plain-English description of each
  one, and the tests attached to it (`not_null`, `relationships`, etc.). `_sources.yml` does
  the same for the raw tables dbt reads from. `dbt_project.yml` holds project-wide
  configuration: the `vars` (year boundaries, segmentation thresholds) and which folder gets
  which materialization (view vs. table). `packages.yml` declares external dependencies
  (`dbt_utils`). The one YAML file deliberately *not* in this repo is `profiles.yml`,
  which holds the BigQuery connection details and stays entirely outside version control.
- *Why*: keeping tests and documentation in YAML rather than scattered as SQL comments means
  dbt can actually *read* them, not just display them for a human. That's what makes `dbt
  test` a runnable command instead of a manual checklist, and it's what makes the
  auto-generated documentation site (see below) possible at all. It's also why tests live
  right next to the model they test, rather than in a separate test suite that's easy to
  forget to update.

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

- *What*: 43 dbt tests spread across staging, intermediate, and marts, all passing against
  real BigQuery data, both locally and automatically in CI.
- *Why*: a test turns "I think this is right" into "the pipeline proves this is right, every
  single run." Each category below is aimed at a different kind of mistake:

| Test type | What it checks | Why it matters |
| --- | --- | --- |
| `unique` / `not_null` | Every row has a real, unique key and no missing required values | Catches a broken join or an accidental duplicate before it silently corrupts downstream numbers |
| `relationships` (both directions) | Every sales line has a matching order, and every order has at least one sales line | Catches data that's fallen out of sync between the two source files |
| `accepted_values` | `order_segmentation` is always exactly `New`, `Returning`, or `VIP` | Catches a typo or a logic bug producing an unexpected label |
| `dbt_utils.expression_is_true` | `net_sales` and `qty` are never negative | Catches obviously invalid data before it reaches a report |
| Singular test (`assert_orders_net_sales_reconciles.sql`) | Each order's total matches the sum of its sales lines | The strongest available cross-check that the two source files actually agree |
| Singular test (`assert_segmentation_matches_known_customer_history.sql`) | A known customer's full order history segments exactly as hand-verified (New, then Returning across a year boundary and a window-aging-out case) | `accepted_values` only checks the label is a valid string; this checks it's the *correct* one, the one test that verifies segmentation correctness, not just shape |

```bash
dbt build   # runs all models + all tests, in dependency order
```

Also runs automatically in CI (`.github/workflows/dbt_build.yml`) on every push, against an
isolated `dbt_ci` target/dataset. See the repo's **Actions** tab.

## Known limitations & future improvements

Deliberate scope decisions, not oversights, each one a real tradeoff made given this
project's actual scale (a solo take-home, ~30k rows) versus what a production system at real
scale would need.

**1. No incremental materialization.**

- *What*: every model is a full-rebuild `table`, not `materialized='incremental'`.
- *Why not fixed*: at billions of rows, rebuilding `fct_orders` from scratch on every run
  would be expensive, incremental models would matter there. At this project's actual volume
  it adds no benefit, and a full rebuild has a real correctness advantage for a take-home: it
  automatically absorbs any backfilled/corrected historical order with zero extra logic.

**2. No CD for the pipeline itself (data promotion or scheduled runs).**

- *What*: CI verifies correctness on every push; nothing automatically promotes data to a
  separate production dataset or runs on a schedule. (The docs site *does* auto-publish on
  every push, that's a small, genuine exception.)
- *Why not fixed*: CD only earns its cost once there's a real downstream consumer depending
  on fresh, promoted data on a schedule. This take-home has a single environment and a
  static, one-time data extract, nothing that would ever need a scheduled refresh, so there's
  no real target for a CD step to serve yet.

## Repo layout

```text
pyproject.toml                : Python dependencies (direct, pinned)
uv.lock                       : full dependency lock (direct + transitive, exact versions)
data/                         : raw source xlsx files
scripts/load_raw_data.py      : one-off loader: xlsx -> raw BigQuery tables
dbt/
  dbt_project.yml             : vars for year boundaries + segmentation thresholds
  packages.yml                : dbt_utils
  models/
    staging/                  : stg_orders, stg_sales + sources.yml
    intermediate/              : int_orders_products_agg, int_orders_enriched
    marts/                     : fct_orders (Ex4), fct_orders_segmented (Ex6)
  macros/segment_from_order_count.sql
  tests/assert_orders_net_sales_reconciles.sql
docs/
  design/2026-09-22-dbt-bigquery-pipeline-design.md   : full design rationale
  SETUP.md                     : BigQuery + dbt environment setup, step by step
  Exercises_Queries.md         : all 6 exercise answers: queries, results, worked examples
  LOG.md                       : running build log
```

## Setup

Full step-by-step walkthrough (GCP project, service account, dbt install, `profiles.yml`) is
in [`docs/SETUP.md`](docs/SETUP.md). Short version:

1. Create a GCP project, enable the BigQuery API, create a service account with
   `BigQuery Data Editor` + `BigQuery Job User`, download its JSON key.
2. `uv sync` (reads `pyproject.toml`/`uv.lock` and creates `.venv` with exact pinned
   versions), then activate it (`source .venv/Scripts/activate`, or `.venv\Scripts\Activate.ps1`
   on PowerShell).
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

- [Design spec](docs/design/2026-09-22-dbt-bigquery-pipeline-design.md): full
  architecture rationale, written before implementation began.
- [Exercises_Queries.md](docs/Exercises_Queries.md): every exercise's answer, queries (dbt +
  raw BigQuery SQL), and a hand-verified worked example of the segmentation logic against a
  real customer's order history.
- [LOG.md](docs/LOG.md): running log of the actual build process and decisions made along
  the way.
