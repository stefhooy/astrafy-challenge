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

- Ran and documented Exercises 1-3 in `docs/Exercises_Queries.md`, structured into two
  sections: the `dbt show --inline` commands/results, and equivalent raw BigQuery SQL run
  directly in Studio as an independent cross-check. Both match exactly.
  - Along the way, refined the BigQuery SQL versions: filtering on `order_date BETWEEN
    '2026-01-01' AND '2026-12-31'` instead of `EXTRACT(YEAR FROM order_date) = 2026`, since
    `fct_orders` is partitioned by `order_date` and a direct range comparison lets BigQuery
    prune partitions (wrapping the partition column in `EXTRACT()` in a `WHERE` clause can
    block pruning). Grouped by month using `FORMAT_DATE('%Y-%m', order_date)` for a
    human-readable, unambiguous label (chosen over `DATE_TRUNC` since we already scope to a
    single year, and over bare `EXTRACT(MONTH ...)` for readability).
  - Results: **Ex1: 2,573 orders in 2026.** Ex2/Ex3: full monthly breakdown in
    `Exercises_Queries.md`. Notable pattern: November has the highest order count (389, ~85%
    above the ~215 monthly average) but the lowest avg products/order (10.48) -- consistent
    with a Black Friday/holiday effect (more orders, each smaller).
- Confirmed all 6 exercises are functionally complete and verified against real BigQuery data
  (re-checked Ex4/5/6 requirements line-by-line against `fct_orders` and
  `fct_orders_segmented`).
- Wrote `docs/../interview-prep-notes.md` (outside the repo, personal prep only) with
  plain-language explanations for the interview: the layered pipeline walkthrough, why
  Ex4/5/6 were built before Ex1/2/3, and a full breakdown of the RANGE BETWEEN segmentation
  logic.

- Re-checked all 5 of the brief's "Technical Requirements" against the repo explicitly (user
  prompted this check): architecture, code quality/reusability, data quality, performance, and
  documentation. Four were already solid; documentation had a real gap -- Ex4/5/6 weren't
  written up in `Exercises_Queries.md` (only Ex1-3 were), and the main `README.md` still had
  placeholder text rather than the "insightful... explaining your architectural choices" the
  brief asks for.
- Extended `docs/Exercises_Queries.md` with Ex4/5/6: model previews, row-count/distribution
  checks (2025: 1,088 orders + 2026: 2,573 = 3,661 total; 2026 segment split New 1,087 /
  Returning 794 / VIP 692, summing to 2,573 exactly), and a concrete cross-year proof point --
  customer 146283's 2025-12-02 order followed by a 2026-07-04 order correctly labeled
  "Returning", direct evidence the segmentation window is using 2025 history to label 2026
  orders. Fixed heading-hierarchy lint warnings along the way (single H1, proper nesting).

- Cross-checked Ex4/5/6 against raw BigQuery SQL (same dual-verification approach as Ex1-3),
  all matching the dbt results exactly. Along the way, built out the strongest single piece of
  evidence in the submission: queried customer 146283's full 5-order history (Sep 2025 -> Nov
  2026) directly against `int_orders_enriched`, and hand-verified every `order_segment` label
  against the rolling 365-day window by hand -- New, then Returning x4, correctly including
  the case where an order's window reaches back across the year boundary into 2025 data, and
  the case where an older 2025 order correctly "ages out" of a later window. Documented the
  full worked example in `Exercises_Queries.md` (Exercise 5 section).

- Rewrote `README.md` with real content, closing the documentation gap identified earlier:
  layered architecture diagram, a "key architectural decisions" section with rationale for
  each major choice (sources vs seeds, FLOAT64->NUMERIC, full-history segmentation,
  RANGE BETWEEN over self-join, macro/var centralization, partitioning/clustering), data
  quality notes, testing summary, repo layout, and condensed setup steps linking out to the
  full guides (`SETUP.md`, `Exercises_Queries.md`, the design spec, `LOG.md`).

- Ran `dbt build` (full pipeline, one command, from a clean state): **43 PASS, 1 WARN, 0
  ERROR** across 4 tables, 2 views, and all 38 tests. Final end-to-end confirmation that
  staging -> intermediate -> marts rebuilds correctly from scratch, not just piecemeal
  per-layer as earlier in the build. The 1 WARN is the same known, documented orphan order
  (5361303) discussed since day one, not a new issue -- confirmed and explained why `warn`
  severity (not `error`) is the right call: it's a single known row in the *source* file
  itself, not something this pipeline introduced, so failing the entire build on it every
  time would be the wrong failure mode. Strengthened the README's data quality section with
  this reasoning explicitly (what happens if a new orphan appears, or if this one gets fixed
  upstream).
- Re-read the full challenge brief (`THC - BI Engineer.docx`) once more end-to-end to confirm
  Part 1 scope is fully covered: all 5 technical requirements + all 6 exercises. Also noted
  the brief's submission instructions ("reply with the PDF from the design challenge + the
  GitHub link") only fully apply once Parts 2/3 exist -- since Cyril confirmed only Part 1 is
  in scope for now, the reply should just be the GitHub repo link, no PDF/Data Studio link
  expected at this stage.

## 2026-09-23

- Did a critical self-review of data engineering standards against the actual code (not just
  the checklist), prompted by prepping for Friday's interview. Found real gaps: `dbt_utils`
  was declared as a dependency but never actually used anywhere in the project (confirmed via
  grep); the orphan-order relationships test only checked sales->orders, never the reverse
  (orders->sales); no test asserted non-negative `net_sales`/`qty`; every model is a full
  `table` rebuild with no incremental strategy despite the brief's billions-of-rows framing;
  no CI.
- Fixed the quick, concrete ones:
  - Added `dbt_utils.expression_is_true` tests (`>= 0`) on `stg_orders.net_sales`,
    `stg_sales.net_sales`, and `stg_sales.qty` -- puts the previously-unused `dbt_utils`
    dependency to real use, and turns a manually-verified fact ("no negative values in this
    data") into an enforced guarantee.
  - Added the missing reverse `relationships` test: `stg_orders.order_id` -> `stg_sales`,
    confirming every order has at least one sales line (error severity, not warn -- this
    direction has zero known exceptions, unlike the sales->orders direction).
  - `dbt test --select staging`: 16 PASS, 1 WARN (same known orphan, unaffected), 0 ERROR --
    new tests pass cleanly.
- Added `.github/workflows/dbt_build.yml`: a basic CI workflow running `dbt deps` + `dbt build`
  against BigQuery on every push, using a service-account key stored as a GitHub Actions secret
  (`GCP_SA_KEY` + `GCP_PROJECT_ID`). Builds into an isolated `dbt_ci` target/dataset, separate
  from the local `dbt_dev` one, so CI runs never clobber local dev state. Documented as a real
  production-readiness gap that's now closed, rather than just explained away verbally.
- Left two gaps as documented, explained tradeoffs rather than implemented, given take-home
  scope: incremental materialization (would matter at real billions-of-rows scale; not
  necessary at this data's actual ~30k row volume) and dev/prod environment separation (only
  one real environment exists for a solo take-home; the CI target already demonstrates the
  pattern of environment-specific targets/datasets).

### Next up

- Final review pass before submission (re-read design spec, README, and all dbt docs for
  consistency).
- Add the `GCP_SA_KEY`/`GCP_PROJECT_ID` secrets to the GitHub repo so the new CI workflow
  actually runs, and confirm it passes on GitHub's side (not just locally).
- Reply to the recruiter's take-home email with the GitHub repo link, per the brief's
  submission instructions (Part 1 only -- no PDF/Data Studio link expected).
