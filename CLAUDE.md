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
- **Gold** — Implemented with dbt (dbt-databricks) under `src/dbt/`. Dimensional
  model written to schema `olist_gold`: a **staging** layer (views over silver) +
  **dimensions**, **facts**, and **aggregates** (tables). See §8 for the full
  model inventory.

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
│   │   ├── order_items_silver.ipynb
│   │   ├── order_payments_silver.ipynb
│   │   ├── order_reviews_silver.ipynb
│   │   └── geolocation_silver.ipynb
│   └── dbt/                            # gold layer (dbt-databricks)
│       ├── dbt_project.yml             # project 'dbt_olist', profile 'olist'
│       ├── profiles.yml                # databricks targets (env_var: DBT_HTTP_PATH, DBT_TOKEN)
│       ├── packages.yml                # dbt_utils
│       └── models/
│           ├── staging/                # views in olist_gold (1:1 over silver, renamed cols)
│           │   ├── _sources.yml        # sources → olist_silver.*
│           │   ├── _staging.yml        # tests
│           │   └── stg_*.sql           # 8 staging models
│           └── marts/                  # tables in olist_gold
│               ├── dimensions/         # dim_regions, dim_geolocation, dim_categories,
│               │                       #   dim_products, dim_customers, dim_sellers
│               ├── facts/              # fact_orders, fact_order_items
│               └── aggregates/         # agg_delivery_vs_satisfaction,
│                                       #   agg_delivery_by_seller, agg_delivery_by_customer_region
├── resources/                # Asset Bundle resources (included via databricks.yml)
│   ├── vars.yml              # variable declarations (catalog, schemas, warehouse_id, table names)
│   ├── targets/
│   │   ├── dev.yml           # dev target (default, mode development)
│   │   └── prod.yml          # prod target (mode production, catalog → olist_project_prod)
│   └── jobs/                 # Databricks Workflows wiring the medallion layers
│       ├── olist_bronze_layer.yml   # 1 task: raw_ingestion (kagglehub env)
│       ├── olist_silver_layer.yml   # silver_setup → 8 parallel silver notebooks
│       └── olist_gold_layer.yml     # dbt deps/run/test (dbt-databricks env)
├── tests/                    # conftest.py + sample_taxis_test.py (bundle template, not yet real tests)
├── .gitignore
├── CLAUDE.md
├── databricks.yml            # Asset Bundle entrypoint (bundle name + include: resources/**)
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

> Note: the `*_order_*` notebook files are named `order_items_silver.ipynb`,
> `order_payments_silver.ipynb`, `order_reviews_silver.ipynb`, but the Delta
> tables they create are `order_items_silver`, `order_payments_silver`,
> `order_reviews_silver` (singular `order`).

**Execution order:** `silver_setup` must run before any other silver notebook.

---

## 8. Gold layer — dbt (`src/dbt/`)

Implemented with **dbt-databricks**. dbt project `dbt_olist`, profile `olist`.
The dbt project under `src/dbt/` is the source of truth. **Staging + dimensions +
facts + aggregates are all implemented.**

### Project config

- **Two layers, both written to schema `olist_gold`:**
  - `staging/` → materialized as **views** (1:1 over silver, column renames only).
  - `marts/` (dimensions + facts + aggregates) → materialized as **tables**.
- **Catalog** comes from `var('silver_catalog')`, defaulted from
  `env_var('DBT_CATALOG', 'olist_project_dev')` in `dbt_project.yml`.
- **Sources** (`_sources.yml`) point to `olist_silver.*` (catalog from the same
  var). Connection (`profiles.yml`) reads `DBT_HTTP_PATH` and `DBT_TOKEN` from env.
- **Packages**: `dbt_utils` (`packages.yml`).

### Staging (views, 1:1 over silver)

`stg_customers`, `stg_sellers`, `stg_products`, `stg_orders`, `stg_order_items`,
`stg_order_payments`, `stg_order_reviews`, `stg_geolocation`.

- `stg_geolocation` is special: it **UNION ALLs** zip/city/state from
  `geolocation_silver` (with lat/lon) plus `sellers_silver` and `customers_silver`
  (lat/lon NULL), to get a complete zip→region coverage. Not deduplicated here —
  aggregation happens in the dimensions.

### Dimensions (`marts/dimensions/`)

- `dim_regions` — surrogate key `id` via
  `dbt_utils.generate_surrogate_key(['geolocationCityName','geolocationState'])`,
  one row per distinct (`city`, `stateName`). This is the city/region dimension
  (replaces the planned `dim_cities`).
- `dim_geolocation` — one row per `zipCodePrefix`: AVG `latitude`/`longitude`, plus
  `regionId` = the **dominant** region for that zip (most frequent city/state match
  to `dim_regions`, tie-broken by `regionId`, via `qualify row_number()`).
- `dim_categories` — surrogate key `id` from `productCategoryName`, column `name`.
- `dim_products` — `id`, `categoryId` (FK → `dim_categories`, joined on name with
  `<=>` null-safe equality), plus physical attributes (`nameLength`,
  `descriptionLength`, `photosQty`, `weightG`, `lengthCm`, `heightCm`, `widthCm`).
- `dim_customers` — `id`, `uniqueId`, `zipCodePrefix` (FK → `dim_geolocation`).
- `dim_sellers` — `id`, `zipCodePrefix` (FK → `dim_geolocation`).

### Facts (`marts/facts/`)

- `fact_orders` — one row per order. Columns: `id`, `customerId`,
  `fulfillmentStatus` (= `orderStatus`), `avgReviewScore`, `purchaseDate`, and
  time metrics **in hours**: `processingHours`, `deliveryHours`, `courierHours`,
  `totalTimeHours`, `estimatedHours`, `deliveryDelayHours`, plus the `isLate` flag.
  - **Time metrics are stored in HOURS** (`timestampdiff(HOUR, ...)`), the atomic
    grain. Days should be derived downstream (`hours / 24.0`), never truncated
    with `timestampdiff(DAY, ...)`. This preserves resolution for ranking the
    worst delivery times.
  - `isLate` is ternary: `null` when the order was never delivered, `true`/`false`
    only for delivered orders. Consumers must filter `isLate is not null` (or
    delivered orders) before computing late rates.
  - `avgReviewScore` is the **average** review score per order (a continuous
    decimal), since an order can have several reviews. It is NOT the discrete
    1–5 enum; `accepted_range(min:1, max:5)` applies, not `accepted_values`.
- `fact_order_items` — one row per item (grain `orderId + orderItemId`): `productId`,
  `sellerId`, `price`, `freightValue`.

### Aggregates (`marts/aggregates/`)

All three are late-delivery analytics built on `fact_orders` (filtered to
`isLate is not null`, i.e. delivered orders only) and share the metric columns
`totalOrders`, `lateOrders`, `lateRatePct` (`lateOrders * 100.0 / totalOrders`).

- `agg_delivery_vs_satisfaction` — one row per rounded review score. Grouped by
  `coalesce(round(avgReviewScore), -1)` (the `-1` bucket = orders with no review),
  so the satisfaction key ranges -1..5.
- `agg_delivery_by_seller` — one row per `sellerId`. Joins `fact_order_items` →
  `dim_sellers` and dedups to order/seller pairs before aggregating against
  `fact_orders`.
- `agg_delivery_by_customer_region` — one row per `stateName`. Resolves each order's
  region via `dim_customers` → `dim_geolocation` → `dim_regions`.

> Note: the region aggregate is keyed by **customer state** (`agg_delivery_by_customer_region`),
> replacing the originally planned `agg_delivery_by_state`.

### Tests (in `_*.yml` alongside models)

- Staging: `not_null` / `unique` on keys.
- Dimensions: `not_null` + `unique` on surrogate keys; `relationships` FKs
  (`dim_products.categoryId` → `dim_categories`, `dim_customers`/`dim_sellers`
  `.zipCodePrefix` → `dim_geolocation`, `dim_geolocation.regionId` → `dim_regions`);
  `dbt_utils.unique_combination_of_columns` on `dim_regions(city, state)`.
- Facts: `fact_orders` — `fulfillmentStatus` `accepted_values` (order-status enum),
  `avgReviewScore` `accepted_range(1..5)`; `fact_order_items` —
  `unique_combination_of_columns(orderId, orderItemId)`, `relationships` to
  `fact_orders`/`dim_products`/`dim_sellers`, `accepted_range(min:0)` on
  `price`/`freightValue`.
- Aggregates: `not_null` + `unique` on the grouping key (`avgReviewScore`,
  `sellerId`, `stateName`); `accepted_range(min:0)` on `totalOrders`/`lateOrders`,
  `accepted_range(0..100)` on `lateRatePct`; `agg_delivery_vs_satisfaction` uses
  `accepted_range(-1..5)` (the `-1` no-review bucket); `agg_delivery_by_seller.sellerId`
  has a `relationships` FK → `dim_sellers`.

### Status

All gold layers (staging, dimensions, facts, aggregates) **and** orchestration
are now implemented. See §11 for the Workflows that wire bronze → silver → dbt.

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
- **Bundle resources**: `databricks.yml` is now just the entrypoint — it defines
  `bundle` (name + uuid) and `include: resources/*.yml` + `resources/**/*.yml`.
  Everything else lives under `resources/` (see §11): variables in `vars.yml`,
  targets in `targets/dev.yml` + `targets/prod.yml`, and the three Workflows in
  `jobs/`. The `dev` target is `default: true`; `prod` overrides `catalog` to
  `olist_project_prod`.
- This file is a living document — update it whenever a decision is resolved.

---

## 11. Orchestration — Databricks Workflows (`resources/`)

Bundle config is split out of `databricks.yml` into `resources/`, auto-included
via `include: resources/*.yml` + `resources/**/*.yml`.

### Layout

- **`resources/vars.yml`** — all variable declarations (each with a `default`):
  `catalog` (`olist_project_dev`), `bronze_schema`/`silver_schema`/`gold_schema`
  (`olist_bronze`/`olist_silver`/`olist_gold`), `warehouse_id`, `metadata_table`,
  plus per-table name vars (`raw_olist_*` bronze tables + `*_silver` table names)
  passed into the notebooks as `base_parameters`.
- **`resources/targets/dev.yml`** — `dev` target (`mode: development`,
  `default: true`), workspace host, `olist_group_dev` `CAN_MANAGE`, and a
  `run_as` service principal.
- **`resources/targets/prod.yml`** — `prod` target (`mode: production`),
  `root_path` under the deploying user, overrides `catalog → olist_project_prod`,
  `olist_group_prod` `CAN_MANAGE`, and its own `run_as` service principal.

### Jobs (`resources/jobs/`)

Three jobs, one per medallion layer (no cross-job trigger wired yet — run in
order bronze → silver → gold):

- **`olist_bronze_layer.yml`** (`Olist Bronze Layer`) — single task
  `raw_ingestion` running `src/bronze/olist_bronze.ipynb` on a serverless
  `environments` spec (`environment_version: "5"`) with `kagglehub` as a
  dependency. Params: `catalog`, `bronze_schema`, `metadata_table`.
- **`olist_silver_layer.yml`** (`Olist Silver Layer`) — `silver_setup` task
  first, then 8 silver notebook tasks each with `depends_on: silver_setup` (so
  they fan out in parallel after setup). Each task passes `catalog`,
  `bronze_schema`, its `raw_olist_*` source table, `silver_schema`, and its
  `*_silver` target table.
- **`olist_gold_layer.yml`** (`Olist Gold Layer`) — single `dbt_task` `dbt_gold`
  on a `dbt` serverless env (`dbt-databricks>=1.0.0,<2.0.0`), `project_directory:
  ../../src/dbt`, `catalog`/`schema`/`warehouse_id` from vars, running
  `dbt deps` → `dbt run` → `dbt test` (both with
  `--vars '{silver_catalog: ${var.catalog}}'`).

> `email_notifications.on_failure` is scaffolded but commented out in all three
> job files.

---
