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
| --- | --- |
| Platform | Databricks (Free Edition) |
| Packaging & deployment | Databricks Asset Bundles |
| Storage format | Delta Lake |
| Processing | PySpark / Spark SQL |
| Silver → Gold transformations | dbt (dbt-databricks) |
| Orchestration | Databricks Workflows |
| Source ingestion | kagglehub (Kaggle API) |
| Python tooling | pyproject.toml |
| Version control | Git / GitHub |

---

## 3. Medallion architecture

- **Bronze** — Raw data as received from Kaggle. All columns loaded as `STRING`
  (`inferSchema=False`). One Delta table per source CSV, plus audit columns
  `ingestionTimestamp` and `sourceFile`. Re-processing is gated by a version
  check against `olist_source_metadata` — only runs if a new Kaggle dataset
  version is detected. Uses `mode("overwrite")` (full reload per version).
- **Silver** — Cleaned, typed, and validated data. Explicit casts, UUID
  validation, timestamp parsing with explicit format. Loaded via
  `MERGE INTO` for idempotent reprocessing. All tables include a
  `processedTimestamp` audit column.
- **Gold** — In progress. Implemented with dbt (dbt-databricks) under
  `src/dbt/`. Dimensional model (facts + dimensions + aggregates) targeting the
  business question. (The dbt project itself is out of scope for this doc.)

Flow: `Kaggle → bronze (raw STRING Delta) → silver (typed, clean) → gold (dbt)`

---

## 4. Design decisions

1. **Automated ingestion via kagglehub.** Ingestion is a pipeline step, not a
   manual download.
2. **`inferSchema=False` in bronze.** All columns land as STRING, preserving
   the raw source exactly (e.g. zip codes with leading zeros). Explicit casting
   happens only in silver.
3. **Delta MERGE for silver upserts.** Each silver notebook uses the pattern:
   `CREATE TABLE IF NOT EXISTS` → transform → `createOrReplaceTempView` → SQL
   `MERGE INTO`. This is idempotent and safe for incremental reprocessing.
4. **Bronze uses overwrite, not MERGE.** Bronze tables are fully replaced when a
   new Kaggle dataset version is ingested. Idempotency is handled by the
   `olist_source_metadata` version check, not by MERGE.
5. **Timestamps parsed with explicit format.** All `to_timestamp()` calls use
   `"yyyy-MM-dd HH:mm:ss"` explicitly. Never rely on Spark's auto-detection.
6. **UUID validation before silver load.** All ID columns are validated with
   `rlike("^[0-9a-fA-F]{32}$")` before writing to silver. Invalid rows are
   silently dropped (expected: they are malformed source records).
7. **City/state kept denormalized in silver.** `customerCity`, `customerState`,
   `sellerCity`, `sellerState` are stored as plain strings. Surrogate key
   dimension extraction (`dim_cities`) is deferred to gold/dbt.
8. **`processedTimestamp` on all silver tables.** Records when the row was last
   written by the pipeline. Updated on every MERGE match.
9. **`autoOptimize` on all Delta tables.** Both `optimizeWrite` and `autoCompact`
   are set via TBLPROPERTIES on bronze and silver tables.
10. **Databricks Free Edition filesystem constraints apply.** Raw CSVs are stored
    in Volumes at `/Volumes/{catalog}/{bronze_schema}/raw_data`. Do not assume
    classic DBFS paths.

---

## 5. Repository structure

```text
.
├── .databricks/              # local bundle state (generated)
├── .vscode/                  # editor settings
├── fixtures/                 # sample data fixtures for tests (currently only .gitkeep)
├── src/
│   ├── bronze/
│   │   └── olist_bronze.ipynb          # ingestion: Kaggle → Volumes → Delta
│   ├── silver/
│   │   ├── silver_setup.ipynb          # creates catalog + silver schema
│   │   ├── customers_silver.ipynb
│   │   ├── sellers_silver.ipynb
│   │   ├── products_silver.ipynb
│   │   ├── orders_silver.ipynb
│   │   ├── orders_items_silver.ipynb
│   │   ├── orders_payments_silver.ipynb
│   │   ├── orders_reviews_silver.ipynb
│   │   └── geolocation_silver.ipynb
│   └── dbt/                            # gold layer (dbt-databricks) — see dbt project
├── tests/                    # conftest.py + sample_taxis_test.py (bundle template, not yet real tests)
├── .gitignore
├── CLAUDE.md
├── databricks.yml            # Asset Bundle config (bundle, variables, dev/prod targets)
├── pyproject.toml            # Python packaging and dependencies
└── README.md
```

---

## 6. Source data (Olist bronze tables)

All tables live in `{catalog}.olist_bronze.*`. All columns are STRING.

| Bronze table | Description |
| --- | --- |
| `olist_orders` | Orders with status and all timestamps |
| `olist_order_items` | Line items per order (product, seller, price, freight) |
| `olist_order_payments` | Payment records per order |
| `olist_order_reviews` | Customer reviews and satisfaction scores |
| `olist_customers` | Customers with zip code and city/state |
| `olist_sellers` | Sellers with zip code and city/state |
| `olist_products` | Product catalog |
| `olist_geolocation` | Lat/lon coordinates by zip code prefix (has duplicates) |
| `product_category_name_translation` | Category name PT → EN mapping |

Primary join keys: `order_id`, `customer_id`, `seller_id`, `product_id`.

---

## 7. Silver layer — tables and MERGE keys

All tables live in `{catalog}.olist_silver.*`.

| Silver table | MERGE key | Notes |
| --- | --- | --- |
| `customers_silver` | `customerId` | `customerUniqueId` also UUID-validated; `customerZipCodePrefix` kept as STRING |
| `sellers_silver` | `sellerId` | City/state as denormalized strings |
| `products_silver` | `productId` | LEFT JOIN with translation + `coalesce` → English category; products without translation keep portuguese category |
| `orders_silver` | `orderId` | All timestamps parsed with explicit format |
| `order_items_silver` | `orderId + orderItemId` | `shippingLimitDate` parsed with `to_timestamp()` |
| `order_payments_silver` | `orderId + paymentSequential` | |
| `order_reviews_silver` | `orderId + reviewId` | `reviewCreationTimestamp` + `reviewAnswerTimestamp` |
| `geolocation_silver` | `geolocationZipCodePrefix` | Deduplicated in silver: one row per zip (AVG lat/lon, `first` non-null city/state) |

> Note: the `*_order_*` notebook files are named `orders_items_silver.ipynb`,
> `orders_payments_silver.ipynb`, `orders_reviews_silver.ipynb`, but the Delta
> tables they create are `order_items_silver`, `order_payments_silver`,
> `order_reviews_silver` (singular `order`).

**Execution order:** `silver_setup` must run before any other silver notebook.

---

## 8. Gold layer — in progress (dbt, under `src/dbt/`)

Implemented with **dbt-databricks**. Target model (this section documents the
intended design; the dbt project under `src/dbt/` is the source of truth):

### Facts

- `fct_orders` — one row per order; derived metrics: `delivery_days`,
  `estimated_days`, `delay_days`, `is_late`, `review_score`
- `fct_order_items` — one row per item; price, freight, seller

### Dimensions

- `dim_customers` — customer location (city, state, lat/lon via geolocation)
- `dim_sellers` — seller location
- `dim_products` — product with English category
- `dim_cities` — surrogate key via `dbt_utils.generate_surrogate_key(['city_name', 'state'])`

### Aggregates

- `agg_delivery_by_seller` — avg delivery days, avg review score, late rate
- `agg_delivery_by_state` — same metrics grouped by state
- `agg_delivery_vs_satisfaction` — delivery days bucketed vs avg review score

dbt sources point to `olist_silver.*`. dbt tests should cover `not_null`,
`unique`, `relationships`, and `accepted_values` (e.g. `review_score` 1–5,
`order_status` enum).

---

## 9. Conventions

- **Tables**: `snake_case`. **Columns**: `camelCase`.
- **Schema prefix by layer**: `olist_bronze.olist_orders`, `olist_silver.orders_silver`, etc.
- **Every transformation must be idempotent** (re-runnable without duplicating data).
- **Timestamps**: always use `to_timestamp(col, "yyyy-MM-dd HH:mm:ss")`.
  Never `.cast("timestamp")` — format auto-detection is unreliable.
- **Numeric/string casts**: `.cast()` is safe (returns NULL on failure, never throws).
  This is the standard approach for silver.
- **dbt**: include `tests` (not_null, unique, relationships) on all gold models.

---

## 10. Notes for Claude Code

- **Bronze MERGE decision**: bronze uses `overwrite`, not MERGE. Do not change
  this — the version check in `olist_source_metadata` is the idempotency gate.
- **Silver setup dependency**: `silver_setup.ipynb` must be the first step in
  any silver workflow. Other silver notebooks assume the schema already exists.
- **Geolocation already deduplicated**: `geolocation_silver` is aggregated in
  silver to one row per zip prefix (`groupBy` zip → AVG lat/lon, `first`
  non-null city/state). Downstream joins on zip no longer need to aggregate.
- **products_silver LEFT JOIN**: a `LEFT JOIN` on the translation table with
  `coalesce(english, portuguese)` — products without an English translation keep
  their Portuguese category name (they are NOT dropped).
- **Volume path resolved**: `/Volumes/{catalog}/{bronze_schema}/raw_data`.
- **Bundle resources**: `databricks.yml` defines only `bundle`, `variables`
  (`catalog`, `bronze_schema`, `silver_schema`, `gold_schema`) and the
  `dev`/`prod` targets, plus `include: resources/*.yml`. The `resources/` folder
  does not exist yet — no jobs/pipelines/Workflows are defined. Add orchestration
  there when ready.
- This file is a living document — update it whenever a decision is resolved.

---

## Code review policy
Whenever the user asks to review, audit or validate code (any phrasing, any
language — e.g. "revisa este código", "review this", "audita la capa silver",
"checkea antes del PR"), ALWAYS delegate to the `de-code-reviewer` subagent.
Do not use the generic/built-in code review for these requests.