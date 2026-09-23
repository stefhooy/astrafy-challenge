# Environment Setup: BigQuery + dbt

Do this once, before any dbt model or the raw-data loader script is run. Matches the tooling
section of
[`docs/design/2026-09-22-dbt-bigquery-pipeline-design.md`](design/2026-09-22-dbt-bigquery-pipeline-design.md):
service-account key auth (no `gcloud`/`bq` CLI required), dbt-core + dbt-bigquery in a
project-local virtual environment.

## 1. GCP project

1. Go to https://console.cloud.google.com/ and sign in with the Google account you want to use.
2. Create a new project (or pick an existing one you're happy to use for this):
   top navbar → project selector → **New Project** → name it e.g. `astrafy-challenge` → Create.
3. Note the **Project ID** (not the display name: the unique id, e.g. `astrafy-challenge-123456`).
   You'll need it for `profiles.yml`.

   **Project ID for this challenge: `astrafy-challenge-509412`**
4. BigQuery's free tier (1 TB queried/month, 10 GB storage) covers this project's data volume
   (~30k rows) with room to spare. No billing account is required to stay within it, though
   Google may still ask you to attach one to unlock the project.

## 2. Enable the BigQuery API

Console → search bar → "BigQuery API" → **Enable** (if not already on by default for new
projects).

## 3. Service account + key

1. Console → **IAM & Admin** → **Service Accounts** → **Create Service Account**.
2. Name it e.g. `dbt-runner`.
3. Grant it two roles:
   - `BigQuery Data Editor` (create/write datasets and tables)
   - `BigQuery Job User` (run queries/dbt jobs)
4. Finish creation, then open the service account → **Keys** tab → **Add Key** → **Create new
   key** → type **JSON** → Create. This downloads a `.json` key file.
5. Move that file somewhere local and stable, e.g.
   `C:\Users\steve\.secrets\astrafy-challenge-key.json`, **not** inside the repo folder. The
   repo's `.gitignore` already blocks `*.json`, but keeping secrets outside the repo entirely is
   safer than relying on gitignore.

## 4. Python environment + dbt

Uses [`uv`](https://docs.astral.sh/uv/) (a fast Python package/environment manager) rather
than plain `pip`/`venv`: it resolves and installs packages significantly faster (a Rust-based
resolver instead of `pip`'s pure-Python one), which matters here since `dbt-core` pulls in a
fairly large dependency tree. `uv venv` creates the virtual environment, and `uv pip install`
is a drop-in replacement for `pip install` that reads/writes the same environment, so
everything downstream (activating the venv, running `dbt`, etc.) works exactly as it would
with plain `pip`. From the repo root:

```bash
cd "/c/Users/steve/OneDrive/Astrafy/astrafy-challenge"
uv venv
source .venv/Scripts/activate   # Git Bash on Windows
uv pip install dbt-core dbt-bigquery google-cloud-bigquery
```

(PowerShell equivalent for activation: `.venv\Scripts\Activate.ps1`)

No `uv`? The plain `pip`/`venv` equivalent works the same way:

```bash
python -m venv .venv
source .venv/Scripts/activate
pip install --upgrade pip
pip install dbt-core dbt-bigquery google-cloud-bigquery
```

## 5. dbt connection profile

dbt reads connection config from `~/.dbt/profiles.yml` (outside the repo, so credentials never
get committed). Create/edit it:

```yaml
astrafy_challenge:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: <your-gcp-project-id>
      dataset: dbt_dev
      keyfile: C:\Users\steve\.secrets\astrafy-challenge-key.json
      threads: 4
      location: EU   # or US, match wherever you create the BigQuery datasets
```

`astrafy_challenge` here must match the `profile:` value in `dbt/dbt_project.yml` once the
project is scaffolded.

## 6. Verify

```bash
cd dbt
dbt debug
```

Should report a successful connection to BigQuery. This confirms auth is correct before we
write a single model.

## Next steps (after this is verified working)

1. Scaffold the dbt project (`dbt/dbt_project.yml`, folder structure).
2. Run `scripts/load_raw_data.py` to load the two Excel files into `raw.orders` / `raw.sales`
   in BigQuery.
3. Build staging → intermediate → marts models, tests, and docs per the design spec.
4. Run `dbt build`, verify Exercises 1-3 numbers, write them into the main `README.md`.
