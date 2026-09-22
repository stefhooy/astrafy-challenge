# Setup & Progress Log

Running log of steps taken for Part 1 of the Astrafy take-home challenge. Newest entries at the
bottom. Companion to [`SETUP.md`](SETUP.md) (the how-to) and
[`superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md`](superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md)
(the why).

## 2026-09-22

- Explored the challenge brief and the two source files (`orders_recrutement.xlsx`,
  `sales_recrutement.xlsx`). Found: real date range is 2025-07-09 → 2026-12-31 (not the brief's
  boilerplate "2022-2023"); no nulls; `orders.net_sales` reconciles exactly with summed
  `sales.net_sales` per order; one orphan `order_id` (5361303) present in `sales` but absent
  from `orders`; inconsistent column naming between the two files (`customers_id`/`customer_id`,
  `orders_id`/`order_id`).
- Confirmed scope with the user: Part 1 (coding challenge) only, per recruiter guidance. Parts 2
  (LookML) and 3 (dashboard design) are out of scope for this repo.
- Brainstormed and agreed on the architecture: raw BigQuery tables + dbt sources (not seeds),
  staging → intermediate → marts layering, rolling-12-month segmentation logic computed over
  full order history, year boundaries as dbt `vars`, BigQuery partitioning/clustering on the
  marts. Full rationale in the design spec.
- Created local folder `astrafy-challenge`, `git init`, connected to GitHub remote
  `https://github.com/stefhooy/astrafy-challenge.git`.
- Decided what goes in the public repo: the confidential challenge `.docx` brief is gitignored;
  the two `.xlsx` data files are tracked (needed to reproduce the pipeline).
- First commit: `.gitignore` + raw data files, pushed to `master`.
- Created `dev` branch for ongoing work.
- Wrote `README.md` (repo overview, all 6 exercises mapped to their deliverables) and
  `docs/superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md` (full design spec).
- Wrote `docs/SETUP.md` (BigQuery + dbt environment setup guide).
- GCP setup (manual, via console, walked through step by step):
  - Created GCP project `astrafy-challenge` → Project ID **`astrafy-challenge-509412`**.
    BigQuery API auto-enabled (console opened straight into BigQuery Studio).
  - Created service account `dbt-runner` with roles `BigQuery Data Editor` +
    `BigQuery Job User`.
  - Generated and downloaded a JSON key for `dbt-runner`; moved it out of the repo folder to
    `C:\Users\steve\.secrets\astrafy-challenge-key.json` (kept outside git entirely, not just
    gitignored).
- Installed `dbt-core`, `dbt-bigquery`, `google-cloud-bigquery` locally via `uv` in a project
  venv (`.venv`).
- Created a dbt `profiles.yml` pointing at the service account key — initially placed at
  `C:\Users\steve\.secrets\.dbt\profiles.yml`; needs to move to the default location
  `C:\Users\steve\.dbt\profiles.yml` (or be used with `--profiles-dir`) for dbt to pick it up
  automatically.

- Installed VS Code extensions: dbt Power User, dbt, SQLFluff, YAML.
- Fixed `profiles.yml` location: moved from `C:\Users\steve\.secrets\.dbt\profiles.yml` to the
  default `C:\Users\steve\.dbt\profiles.yml` dbt expects.
- Confirmed local tooling versions: dbt-core 1.12.5, dbt-bigquery adapter 1.12.1 (both up to
  date).
- Scaffolded the dbt project: `dbt/dbt_project.yml` (profile `astrafy_challenge`, per-layer
  schema/materialization config, `vars` for the mart year boundaries and segmentation
  thresholds) and `dbt/packages.yml` (`dbt_utils`), plus the `models/{staging,intermediate,marts}`,
  `macros/`, `tests/`, `seeds/` folder structure.
- Ran `dbt debug` from `dbt/` — **connection to BigQuery confirmed working** (`All checks
  passed!`), verifying the service account, project, and profile config end-to-end before any
  model code was written.
- Checked the venv for the raw-data-loading dependencies: `google-cloud-bigquery` (3.45.2) and
  `pandas` (3.0.6) present; `openpyxl` (needed by pandas to read `.xlsx`) was missing — install
  triggered.

- Installed `openpyxl` (needed by pandas to read `.xlsx` files).
- Moved the raw data files from `THCAnalyticsInsights/` to `data/` (via `git mv`, preserving
  history) to match the documented repo layout; the confidential `.docx` brief stays in
  `THCAnalyticsInsights/` and remains gitignored.
- Wrote `scripts/load_raw_data.py`: loads `data/orders_recrutement.xlsx` and
  `data/sales_recrutement.xlsx` into BigQuery as `raw.orders` / `raw.sales`, with an explicit
  schema (using `NUMERIC` rather than `FLOAT64` for `net_sales`, to avoid floating-point drift
  on money values) and `WRITE_TRUNCATE` so re-runs are idempotent. Auth via Application Default
  Credentials (`GOOGLE_APPLICATION_CREDENTIALS` env var pointing at the service account key).

- First run of `scripts/load_raw_data.py` failed: `pyarrow.lib.ArrowInvalid` when loading a
  pandas `float64` column straight into a BigQuery `NUMERIC` column via
  `load_table_from_dataframe` (known limitation — that path needs Python `Decimal`-typed
  columns, not `float64`). Decided the fix: keep `net_sales` as `FLOAT64` in the raw tables
  (raw mirrors the source exactly) and cast to `NUMERIC` in the staging layer instead (staging
  is the single place type-cleanup happens). Simpler loader, same precision guarantee
  downstream since nothing queries `raw.*` directly.
- Re-ran the loader successfully: `raw.orders` (3,661 rows) and `raw.sales` (28,361 rows) in
  BigQuery, row counts matching the source files exactly.

- Installed the SQLFluff VS Code extension; needed the `sqlfluff`/`sqlfluff-templater-dbt` CLI
  packages installed separately, and a `.sqlfluff` config (bigquery dialect, dbt templater
  pointed at `./dbt` and the profiles dir) for it to parse Jinja/`ref()`/`source()` correctly.
- Built the staging layer:
  - `models/staging/_sources.yml` — declares `raw.orders` / `raw.sales` as dbt sources with
    column descriptions, including a note on the known sales/orders orphan.
  - `models/staging/stg_orders.sql`, `stg_sales.sql` — rename/cast: resolves the
    `customer_id`/`customers_id` and `order_id`/`orders_id` naming inconsistency, renames
    `date_date` -> `order_date`, casts `net_sales` `FLOAT64` -> `NUMERIC`.
  - `models/staging/_staging.yml` — column docs + generic tests (`unique`/`not_null` on keys),
    plus a `relationships` test on `stg_sales.order_id` -> `stg_orders.order_id` set to `warn`
    severity (not `error`) since the one known orphan order is an accepted, documented
    exception rather than a data-quality bug to block builds on.
  - `tests/assert_orders_net_sales_reconciles.sql` — singular test: fails if any order's
    `net_sales` doesn't match the sum of its `stg_sales` line items (small epsilon for
    floating-point noise from the type cast).

- `dbt deps` installed `dbt_utils` (1.4.1).
- `dbt run --select staging`: both `stg_orders`/`stg_sales` built successfully as views. Fixed
  a deprecation warning along the way -- the `relationships` test's `to`/`field` args needed
  to be nested under `arguments:` per current dbt syntax (this was also what the YAML
  extension's schema had correctly flagged as an error earlier; that flag turned out to be
  right, not a false positive as first assumed).
- `dbt test --select staging`: **12 PASS, 1 WARN, 0 ERROR**. The single warning is exactly the
  `relationships` test catching the one known orphan order (5361303), as designed. The
  `assert_orders_net_sales_reconciles` singular test also passed, confirming
  `orders.net_sales` matches summed `sales.net_sales` for every order, verified against real
  BigQuery data (not just the earlier local pandas check).

- Built the intermediate layer: `int_orders_products_agg` (qty_product = SUM(qty) per order)
  and `int_orders_enriched` (orders + qty_product + rolling 12-month order count via the
  `UNIX_DATE`/`RANGE BETWEEN` windowed pattern + `order_segment` via
  `macros/segment_from_order_count.sql`), computed over full order history.
- `dbt run --select intermediate` / `dbt test --select intermediate`: both models built as
  tables, **12/12 tests passing**, 0 errors.
- Sanity-checked the segmentation distribution against real BigQuery output before building
  marts on top of it: New 1,747 / Returning 1,121 / VIP 793 (sums to 3,661, matching total
  order count exactly). Noted a caveat worth stating explicitly in the README: since the
  dataset only starts 2025-07-09, orders early in that window are undercounted as "New"
  relative to a customer's true (unobserved, pre-extract) history -- a data-boundary
  limitation, not a pipeline bug.
- Built the marts:
  - `fct_orders` (Ex4): filters `int_orders_enriched` to `var('orders_mart_years')`
    (2025+2026), table materialization, partitioned by `order_date`, clustered by
    `customer_id`.
  - `fct_orders_segmented` (Ex6): filters to `var('segmentation_mart_year')` (2026 only),
    same partitioning, clustered by `order_segmentation` then `customer_id` since
    segment-filtered queries are the expected access pattern.
- `dbt run --select marts` / `dbt test --select marts`: both marts built successfully
  (`fct_orders`: 3,661 rows; `fct_orders_segmented`: 2,573 rows, matching the earlier raw
  2026-order count exactly), **13/13 tests passing**, 0 errors.
- **Full pipeline (staging -> intermediate -> marts) is now built and verified against real
  BigQuery data, all 38 dbt tests passing.** Moving from pipeline construction to answering
  Exercises 1-3 with real query output next.

### Next up

- Run the Ex1-3 queries against `fct_orders`, record the exact SQL + results in the README.
- Write up the final README (setup instructions, all 6 exercise answers, architecture
  summary).
