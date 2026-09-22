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

### Next up
- Fix `profiles.yml` location.
- Scaffold the dbt project (`dbt/dbt_project.yml`, folder structure) and run `dbt debug` to
  verify the BigQuery connection before writing any models.
- Build `scripts/load_raw_data.py` and load `raw.orders` / `raw.sales`.
