"""One-off loader: reads the two challenge Excel extracts and loads them into BigQuery as
raw tables, which dbt sources then build on top of.

Not a dbt seed on purpose — see docs/superpowers/specs/2026-09-22-dbt-bigquery-pipeline-design.md
for the rationale (seeds are for static reference data, not transactional fact data).

Usage:
    # Auth: relies on Application Default Credentials. Point it at the same service
    # account key used by dbt's profiles.yml:
    #   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\\Users\\steve\\.secrets\\astrafy-challenge-key.json"
    #   Git Bash:    export GOOGLE_APPLICATION_CREDENTIALS="/c/Users/steve/.secrets/astrafy-challenge-key.json"

    python scripts/load_raw_data.py --project astrafy-challenge-509412

Re-running is safe: each table is fully replaced (WRITE_TRUNCATE), not appended.
"""

import argparse
from pathlib import Path

import pandas as pd
from google.cloud import bigquery

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"

# net_sales is FLOAT64 here, matching the source data as-is: raw tables mirror the source
# system exactly, they don't clean it. Type normalization (cast to NUMERIC for money-safe
# precision) happens once, downstream, in the staging layer -- the single place types get
# cleaned before anything else consumes them.
ORDERS_SCHEMA = [
    bigquery.SchemaField("date_date", "DATE"),
    bigquery.SchemaField("customers_id", "INT64"),
    bigquery.SchemaField("orders_id", "INT64"),
    bigquery.SchemaField("net_sales", "FLOAT64"),
]

SALES_SCHEMA = [
    bigquery.SchemaField("date_date", "DATE"),
    bigquery.SchemaField("customer_id", "INT64"),
    bigquery.SchemaField("order_id", "INT64"),
    bigquery.SchemaField("products_id", "INT64"),
    bigquery.SchemaField("net_sales", "FLOAT64"),
    bigquery.SchemaField("qty", "INT64"),
]

TABLES = [
    ("orders_recrutement.xlsx", "orders", ORDERS_SCHEMA),
    ("sales_recrutement.xlsx", "sales", SALES_SCHEMA),
]


def load_table(client: bigquery.Client, dataset_ref: str, filename: str, table_name: str,
                schema: list[bigquery.SchemaField]) -> None:
    df = pd.read_excel(DATA_DIR / filename)
    table_id = f"{dataset_ref}.{table_name}"

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
    )
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()

    table = client.get_table(table_id)
    print(f"  {table_id}: loaded {table.num_rows} rows")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="GCP project id")
    parser.add_argument("--dataset", default="raw", help="Raw dataset name (default: raw)")
    parser.add_argument("--location", default="EU", help="BigQuery dataset location (default: EU)")
    args = parser.parse_args()

    client = bigquery.Client(project=args.project)
    dataset_ref = f"{args.project}.{args.dataset}"

    dataset = bigquery.Dataset(dataset_ref)
    dataset.location = args.location
    client.create_dataset(dataset, exists_ok=True)
    print(f"Dataset ready: {dataset_ref} ({args.location})")

    for filename, table_name, schema in TABLES:
        load_table(client, dataset_ref, filename, table_name, schema)

    print("Done.")


if __name__ == "__main__":
    main()
