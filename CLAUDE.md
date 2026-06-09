# CLAUDE.md

> Project context for Claude Code. This file is loaded automatically when the
> repository is opened. Keep it up to date as the project evolves.

---

## 1. Overview

Batch data pipeline on **Databricks** implementing a **Medallion architecture
(bronze / silver / gold)** over the public **Olist** Brazilian E-Commerce dataset
(~100k orders, 2016–2018).

The project is packaged and deployed as a **Databricks Asset Bundle**.

**Business question:**
*How does delivery time impact customer satisfaction, and which sellers /
regions concentrate the worst delivery times?*

---

## 2. Tech stack

| Concern | Technology |
|---------|-----------|
| Platform | Databricks (Free Edition) |
| Packaging & deployment | Databricks Asset Bundles |
| Storage format | Delta Lake |
| Processing | PySpark / Spark SQL |
| silver → gold transformations | dbt (dbt-databricks) |
| Orchestration | Databricks Workflows |
| Source ingestion | kagglehub (Kaggle API) |
| Python tooling | pyproject.toml |
| Version control | Git / GitHub |

---

## 3. Medallion architecture

- **Bronze** — Raw data as received from the source, untransformed. One Delta
  table per source CSV, plus ingestion metadata columns (`_ingested_at`,
  `_source_file`).
- **Silver** — Cleaned and conformed data: correct types, deduplication, null
  handling, validated keys, standardized names. Clean relational model ready to
  be joined.
- **Gold** — Aggregated tables aligned to the business question. Dimensional
  model (facts + dimensions) or ready-to-consume aggregate tables.

Flow: `Kaggle → bronze (raw Delta) → silver (clean) → gold (aggregated)`

---

## 4. Design decisions

1. **Automated ingestion via kagglehub.** Ingestion is a pipeline step, not a
   manual download.
2. **Simulated incremental loads.** The dataset is static; it is processed as if
   arriving in periods, partitioned by month of `order_purchase_timestamp`.
3. **Delta MERGE for upserts.** Loads into bronze/silver use `MERGE INTO` for
   idempotent reprocessing, not blind `overwrite`.
4. **Databricks Free Edition filesystem constraints apply.** Do not assume
   classic DBFS paths. Verify writable locations / volumes before hardcoding
   paths. Document the resolved path once decided.

---

## 5. Repository structure

```
.
├── .databricks/        # local bundle state (generated)
├── .vscode/            # editor settings
├── fixtures/           # sample data fixtures for tests
├── src/                # pipeline source: notebooks and Python modules
├── tests/              # unit and data tests
├── .gitignore
├── CLAUDE.md           
├── databricks.yml      # Asset Bundle config (targets, jobs, pipelines)
├── pyproject.toml      # Python packaging and dependencies
└── README.md           # project documentation + architecture diagram
```

---

## 6. Source data (Olist tables)

Multi-table relational dataset. Main tables:

- `olist_orders` — orders (status, purchase / delivery timestamps)
- `olist_order_items` — items per order (product, seller, price, freight)
- `olist_order_payments` — payments per order
- `olist_order_reviews` — reviews and satisfaction score
- `olist_customers` — customers and their location
- `olist_sellers` — sellers and their location
- `olist_products` — product catalog
- `olist_geolocation` — coordinates by zip code prefix
- `product_category_name_translation` — category translation PT→EN

Primary join keys: `order_id`, `customer_id`, `seller_id`, `product_id`.
The business question relies mainly on orders, order_items, reviews, sellers and
customers.

---

## 7. Conventions

- **PySpark**: tables in `snake_case` and columns in `camelCase`.
- Layer as schema prefix: `olist_bronze.olist_orders`, `olist_silver.orders`, etc. Keep a
  single consistent convention.
- Every transformation step must be **idempotent** (re-runnable without
  duplicating data).
- Comment the *why* of non-trivial transformations, not the *what*.
- dbt: include `tests` (not_null, unique, relationships) on silver/gold models.

---

## 8. Notes for Claude Code

- Verify Databricks Free Edition filesystem constraints (filesystem / volumes)
  before proposing file or write paths. Do not assume.
- Bundle resources (jobs, pipelines) are defined in `databricks.yml`. Keep
  deployment configuration there.
- Keep deliverables explainable from the README in 30 seconds: what problem it
  solves, architecture diagram, how to run it.
- This file is a living document — update it whenever a decision is resolved.