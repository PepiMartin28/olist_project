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
  validation (strict on merge keys, null-out for FKs — see §4.6), timestamp
  parsing with `try_to_timestamp` + explicit format. Loaded via
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
5. **Timestamps parsed with `try_to_timestamp` + explicit format.** All timestamp
   parsing uses `expr("try_to_timestamp(col, 'yyyy-MM-dd HH:mm:ss')")`. The format
   is always explicit (never rely on Spark's auto-detection), and the `try_`
   variant returns NULL on unparseable input instead of throwing — required on
   serverless compute, where ANSI mode is enabled by default and plain
   `to_timestamp` would **fail the job** on a single malformed value.
6. **UUID validation: strict on the merge key, null-out for FKs.** All ID columns
   are validated with `rlike("^[0-9a-fA-F]{32}$")`. The validation is applied
   differently depending on the column's role:
   - **Merge-key columns** (the table's PK and any UUID that is part of the MERGE
     `ON`) are validated in the `where` clause — invalid rows are dropped (they
     cannot form a key). E.g. `orders.orderId`, `order_items.(orderId)`,
     `order_reviews.(orderId, reviewId)`, `order_payments.orderId`, `sellers.sellerId`.
   - **Foreign-key / attribute UUIDs** are NOT used to drop rows. Instead they are
     null-ed when invalid via
     `when(col(x).rlike(...), col(x)).otherwise(None)`, so the row survives with a
     NULL FK rather than being lost. Applies to `orders.customerId`,
     `order_items.productId` / `.sellerId`, and `customers.customerUniqueId`.
   - Rationale: dropping an order because its `customerId` is malformed would lose
     the delivery timestamps we actually analyze. Nulling the FK is also
     consistent with gold, which already filters `where sellerId is not null`.
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
11. **Bronze CSV read is multiline-safe.** Bronze reads each CSV in a single loop
    with `multiLine=True, escape='"'` so free-text fields that contain embedded
    newlines / quotes (notably `review_comment_message` in `olist_order_reviews`)
    are not split across rows. The Delta write uses
    `.option("overwriteSchema", "true")` so the full reload is resilient to schema
    changes between dataset versions. There is exactly **one** ingestion loop — do
    not reintroduce a second pass (an earlier duplicate loop re-read without the
    multiline options and corrupted the reviews table).
12. **`dropDuplicates` is a defensive no-op, kept non-deterministic by design.**
    Silver dedups on the merge key (`dropDuplicates([...keys])`). In the Olist
    source these keys are already unique, so this only guards against fully
    identical rows — where the chosen row is irrelevant. A deterministic
    tie-breaker was deliberately **not** added: the source has no recency column
    (`processedTimestamp` is `current_timestamp()`, identical across the batch), so
    "latest wins" cannot be implemented faithfully and a `row_number()` ordering
    would only fake a guarantee the data does not provide.
13. **Silver logic lives in an installable wheel, not inline in each notebook.**
    The per-table transformations (`parse_timestamp`, `is_valid_uuid`,
    `null_invalid_uuid`, `with_processed_timestamp`) and the `MERGE` builder
    (`build_merge_sql` / `merge_into`) live in the `olist_silver` package
    (`src/olist_silver/`). The package is built as a wheel by the bundle
    (`artifacts.olist_silver_wheel` in `databricks.yml`, `uv build --wheel`) and
    installed onto the silver job's serverless `environment` (`dist/*.whl`). Each
    silver notebook just `import`s the helpers, so the hand-written `MERGE` SQL
    (previously duplicated 8×, and the source of column-drift bugs) exists in one
    place. `merge_into` supports composite keys (`order_items`, `order_payments`,
    `order_reviews`) and derives the update columns from the source DataFrame's
    schema, so adding a column to a silver table no longer means editing a MERGE
    by hand. `build_merge_sql` is a pure string builder, decoupled from
    `spark.sql`, so it can be unit-tested without a Spark session.

---

## 5. Repository structure

```text
.
├── .databricks/              # local bundle state (generated)
├── .vscode/                  # editor settings
├── fixtures/                 # sample data fixtures for tests (currently only .gitkeep)
├── src/
│   ├── olist_silver/                   # installable helper package (wheel) for silver
│   │   ├── __init__.py                 # re-exports the public helpers
│   │   └── transformations.py          # parse_timestamp, is_valid_uuid, null_invalid_uuid,
│   │                                   #   with_processed_timestamp, build_merge_sql, merge_into
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
│       ├── macros/                      # delivery_metrics.sql (shared agg metric columns)
│       ├── tests/                       # singular data tests (assert_region_agg_reconciles.sql)
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

- **All written to schema `olist_gold`:**
  - `staging/` → materialized as **views** (1:1 over silver, column renames only).
  - `marts/dimensions` + `marts/facts` → materialized as **tables**.
  - `marts/aggregates` → materialized as **views** (overrides the marts default in
    `dbt_project.yml`).
- **Catalog** comes from `var('silver_catalog')`, defaulted from
  `env_var('DBT_CATALOG', 'olist_project_dev')` in `dbt_project.yml`.
- **Sources** (`_sources.yml`) point to `olist_silver.*` (catalog from the same
  var). Connection (`profiles.yml`) reads `DBT_HTTP_PATH` and `DBT_TOKEN` from env.
  Source **freshness** is configured (`loaded_at_field: processedTimestamp`,
  `warn_after` 24h) and runs as the first step of the gold job (see §11). It is
  **warn-only by design**: only `warn_after` is set (no `error_after`), so
  `dbt source freshness` reports staleness but always exits 0 and never fails the
  job — ingestion is batch / on-new-version, so silver legitimately goes >24h
  stale between Kaggle releases and a hard error gate would cause false failures.
- **Packages**: `dbt_utils` (`packages.yml`).
- **Docs**: every source table and model carries a `description`, and key/metric
  columns are documented. The three repeated aggregate metric columns
  (`totalOrders`, `lateOrders`, `lateRatePct`) use a shared `docs` block
  (`marts/aggregates/_aggregates_docs.md`, referenced via `{{ doc(...) }}`) so the
  late-rate definition is documented in one place. Build the docs site with
  `dbt docs generate` + `dbt docs serve`.

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
These three columns are emitted by the `{{ delivery_metrics() }}` macro
(`macros/delivery_metrics.sql`) — the single source of truth for the late-rate
definition. Each aggregate just supplies its own grouping key and `group by`.

- `agg_delivery_vs_satisfaction` — one row per rounded review score. Grouped by
  `coalesce(round(avgReviewScore), -1)` (the `-1` bucket = orders with no review),
  so the satisfaction key ranges -1..5.
- `agg_delivery_by_seller` — one row per `sellerId`. Joins `fact_order_items` →
  `dim_sellers` and dedups to order/seller pairs before aggregating against
  `fact_orders`.
- `agg_delivery_by_customer_region` — one row per `stateName`. Resolves each order's
  region via `dim_customers` → `dim_geolocation` → `dim_regions` using **LEFT
  joins**: orders whose customer zip does not resolve to a region fall into a
  `'UNKNOWN'` bucket instead of being dropped, so the row counts **reconcile**
  with the total of delivered orders (enforced by a singular test, see Tests).

> Note: the region aggregate is keyed by **customer state** (`agg_delivery_by_customer_region`),
> replacing the originally planned `agg_delivery_by_state`.

### Tests

Schema tests live in `_*.yml` alongside the models. Singular (data) tests live
in `src/dbt/tests/*.sql` (default `test-paths`).

- Staging: `not_null` / `unique` on keys.
- Dimensions: `not_null` + `unique` on surrogate keys; `relationships` FKs
  (`dim_products.categoryId` → `dim_categories`, `dim_customers`/`dim_sellers`
  `.zipCodePrefix` → `dim_geolocation`, `dim_geolocation.regionId` → `dim_regions`);
  `dbt_utils.unique_combination_of_columns` on `dim_regions(city, state)`.
- Facts: `fact_orders` — `fulfillmentStatus` `accepted_values` (order-status enum),
  `avgReviewScore` `accepted_range(1..5)`, plus `accepted_range(min:0)` **at
  `severity: warn`** on the forward-duration metrics (`processingHours`,
  `deliveryHours`, `courierHours`, `totalTimeHours`, `estimatedHours`) — negatives
  flag out-of-order source timestamps without failing the gold job.
  `deliveryDelayHours` is deliberately NOT range-tested (legitimately negative for
  early deliveries). `fact_order_items` —
  `unique_combination_of_columns(orderId, orderItemId)`, `relationships` to
  `fact_orders`/`dim_products`/`dim_sellers`, `accepted_range(min:0)` on
  `price`/`freightValue`.
- Aggregates: `not_null` + `unique` on the grouping key (`avgReviewScore`,
  `sellerId`, `stateName`); `accepted_range(min:0)` on `totalOrders`/`lateOrders`,
  `accepted_range(0..100)` on `lateRatePct`; `agg_delivery_vs_satisfaction` uses
  `accepted_range(-1..5)` (the `-1` no-review bucket); `agg_delivery_by_seller.sellerId`
  has a `relationships` FK → `dim_sellers`.
- Singular: `assert_region_agg_reconciles` — fails if
  `agg_delivery_by_customer_region` drops or double-counts orders vs. the
  delivered-orders count in `fact_orders`.

### Status

All gold layers (staging, dimensions, facts, aggregates) **and** orchestration
are now implemented. See §11 for the Workflows that wire bronze → silver → dbt.

---

## 9. Conventions

- **Tables**: `snake_case`. **Columns**: `camelCase`.
- **Schema prefix by layer**: `olist_bronze.olist_orders`, `olist_silver.orders_silver`, etc.
- **Every transformation must be idempotent** (re-runnable without duplicating data).
- **Timestamps**: always use `expr("try_to_timestamp(col, 'yyyy-MM-dd HH:mm:ss')")`.
  Never `.cast("timestamp")` (format auto-detection is unreliable) and never plain
  `to_timestamp` (throws under serverless ANSI mode — see §4.5).
- **Numeric/string casts**: `.cast()` is safe (returns NULL on failure, never throws).
  This is the standard approach for silver.
- **dbt**: include `tests` (not_null, unique, relationships) on all gold models.
- **dbt SQL aliasing**: relation aliases (tables, CTEs, refs) are **descriptive
  and written without the `as` keyword** (`from {{ ref('fact_orders') }} orders`,
  not `as orders` and not single letters). Column aliases **do** use `as`
  (`avg(latitude) as latitude`).

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
  `dbt deps` → `dbt source freshness` → `dbt run` → `dbt test` (the last three
  with `--vars '{silver_catalog: ${var.catalog}}'`). `source freshness` is
  warn-only (see §8): it logs silver staleness but never fails the job.

> `email_notifications.on_failure` is scaffolded but commented out in all three
> job files.

---

## 12. CI/CD — GitHub Actions (`.github/workflows/`)

One CI workflow plus a manual deploy. The **ruff** and **dbt parse** checks are
offline (no credentials); the **sqlfluff** check uses the dbt templater and is
therefore gated to PRs only (it needs a warehouse connection).

### `ci.yml` — quality checks

Triggers: **push to any branch except `main`** and **PRs targeting `main`**.

- **ruff** (every push + PR, offline) — `ruff check .` + `ruff format --check .`.
  Config in `pyproject.toml` (`line-length = 120`; `builtins = [spark, dbutils,
  display, displayHTML, getArgument]` so the Databricks-injected notebook globals
  don't trip `F821`).
- **dbt parse** (every push + PR, offline) — `dbt deps` + `dbt parse` in
  `src/dbt` (validates models + `_*.yml`). Dummy `DBT_HTTP_PATH`/`DBT_TOKEN` env
  vars just render `profiles.yml`; `parse` never connects.
- **sqlfluff** (`if: pull_request` only) — `sqlfluff lint src/dbt/models` (dialect
  `databricks`) using the **dbt templater** (`.sqlfluff`: `templater = dbt`,
  `project_dir`/`profiles_dir = src/dbt`, `profile = olist`, `target = dev`). The
  dbt templater compiles the project against the **Databricks warehouse**, so it
  needs real credentials — hence it runs only on PRs to main and binds the `dev`
  GitHub Environment (scoping the `DBT_HTTP_PATH`/`DBT_TOKEN` secrets). The job
  installs `sqlfluff-templater-dbt` + `dbt-databricks`, runs `dbt deps`, then
  lints from the repo root. Rules `CP02` (identifier case — columns are camelCase)
  and `RF04` (keywords as identifiers — `name`, `state`) are disabled to match the
  project conventions (§9). Table aliases implicit, column aliases explicit,
  keywords/functions lower-case.

> Why the dbt templater over a jinja stub: it resolves `ref()`, project macros,
> and `dbt_utils.*` for real (no fake stubs), at the cost of needing a warehouse
> connection. The trade-off chosen here is fidelity over offline-on-every-branch:
> sqlfluff only runs at PR time, never exposing secrets to arbitrary branch pushes.
>
> The dbt SQL was normalized once with `ruff format` / `sqlfluff fix` to establish
> a clean baseline (only mechanical/style changes — no logic changed). dbt run
> artifacts are git-ignored: `src/dbt/{dbt_packages,logs,target}/` + `.user.yml`
> (but `package-lock.yml` is committed).

### `deploy.yml` — manual bundle deploy

`workflow_dispatch` only (the **Run workflow** button), with a `target` choice
input (`dev` / `prod`). Steps: `databricks bundle validate` → `databricks bundle
deploy -t <target>`. CLI auth via env (`DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID`,
`DATABRICKS_CLIENT_SECRET` — OAuth M2M service principal).

**Access control (no required reviewers, by design):**

- The job binds `environment: ${{ inputs.target }}`, so the `DATABRICKS_*` secrets
  are **scoped per GitHub Environment** (`dev` / `prod`) — the prod
  service-principal credentials are only readable by the `prod` environment.
- **Who can deploy:** `workflow_dispatch` is only available to repo collaborators
  with **write** access — not anyone.
- **prod is `main`-only:** a guard step hard-fails any `prod` run whose ref isn't
  `main`; pair it with the `prod` environment's deployment-branch rule.

> **Manual GitHub setup required** (not in code): create the `dev` and `prod`
> Environments in repo Settings. Add the three `DATABRICKS_*` secrets (OAuth M2M,
> for `deploy.yml`) to **both**; additionally add `DBT_HTTP_PATH` + `DBT_TOKEN`
> (warehouse HTTP path + PAT, for the sqlfluff dbt-templater check) to the **dev**
> Environment. Restrict the `prod` environment's deployment branch to `main`.

---
