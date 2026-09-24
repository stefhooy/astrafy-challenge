# seeds/

Intentionally empty, not an oversight.

This project loads its raw data (`orders_recrutement.xlsx`, `sales_recrutement.xlsx`) into
BigQuery via `scripts/load_raw_data.py` and reads it through dbt **sources**
(`models/staging/_sources.yml`), not through dbt **seeds**. dbt's own guidance is that seeds
are for small, static reference data (lookup/mapping tables), not transactional fact data,
even at small volume, so seeding the orders/sales data directly would go against that
convention. See the "Raw BigQuery tables + dbt sources, not dbt seeds" section in the main
`README.md` for the full rationale.

This folder, and `seed-paths: ["seeds"]` in `dbt_project.yml`, are kept as standard dbt
project scaffolding in case a genuinely static reference table (e.g. a country-code or
currency lookup) is ever needed, at which point a `.csv` file dropped in here and a
`dbt seed` run is all that's required, no other configuration changes needed.
