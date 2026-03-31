# CLAUDE.md — Agent Guide for northwind-dwh-design

This file provides all context an AI agent needs to make coherent changes to this repository without breaking anything.

---

## Stack and Architecture

| Component | Detail |
|---|---|
| **Language** | Python 3.12 |
| **Package manager** | `uv` |
| **Transform tool** | dbt-core 1.11.7 |
| **Data warehouse** | Google BigQuery (via `dbt-bigquery` 1.11.1) |
| **CI/CD** | GitHub Actions (`claude-code-action`) |

### Architectural pattern: 3-layer Data Warehouse (Medallion)

Data flows through three layers, each with its own BigQuery schema:

```
dl_northwind (source / data lake)
      ↓
stg_northwind  (staging layer — dbt views)
      ↓
dwh_northwind  (warehouse layer — dbt tables: star schema)
      ↓
obt_northwind  (analytics layer — dbt tables: one big tables)
```

- **Source** (`dl_northwind`): raw tables loaded externally; never modified by dbt.
- **Staging** (`stg_northwind`): one view per source table; minimal transformations; adds `ingestion_timestamp`.
- **Warehouse** (`dwh_northwind`): star schema with `dim_*` (dimensions) and `fact_*` (facts); materialized as tables; deduplication applied; date partitioning on fact tables.
- **Analytics OBT** (`obt_northwind`): pre-joined "one big table" views combining facts + dimensions for BI tools; materialized as tables.

---

## Project Structure

```
northwind-dwh-design/
├── .github/
│   └── workflows/
│       └── claude-assistant.yml   # GitHub Actions: triggers Claude Code on @claude mentions
├── docs/
│   └── diagrams/                  # Architecture diagrams (PNG): conceptual, logical, physical, oltp
├── northwind/                     # dbt project root
│   ├── dbt_project.yml            # Project config: name, profile, model paths, materialization settings
│   ├── analyses/                  # dbt analyses (currently empty)
│   ├── macros/                    # dbt macros (currently empty)
│   ├── seeds/                     # dbt seeds (currently empty)
│   ├── snapshots/                 # dbt snapshots (currently empty)
│   ├── tests/                     # dbt tests (currently empty)
│   └── models/
│       ├── staging/
│       │   ├── source.yml         # Source definitions pointing to dl_northwind schema
│       │   └── stg_*.sql          # One staging model per source table
│       ├── warehouse/
│       │   ├── dim_*.sql          # Dimension tables (customer, employee, product, date)
│       │   └── fact_*.sql         # Fact tables (sales, inventory, purchase_order)
│       └── analytics_obt/
│           └── obt_*.sql          # One big tables for analytics (sales_overview, customer_reporting, product_inventory)
├── .gitignore                     # Ignores: dbt-env/, logs/
├── .python-version                # Python 3.12
├── pyproject.toml                 # Python project config; dependencies: dbt-core, dbt-bigquery
├── uv.lock                        # uv lockfile — do not edit manually
└── CLAUDE.md                      # This file
```

---

## Code Conventions

### Naming conventions

| Layer | Prefix | Example |
|---|---|---|
| Staging | `stg_` | `stg_orders.sql` |
| Dimension | `dim_` | `dim_customer.sql` |
| Fact | `fact_` | `fact_sales.sql` |
| One big table | `obt_` | `obt_sales_overview.sql` |

- **File names**: lowercase, snake_case, prefixed by layer.
- **SQL identifiers**: lowercase, snake_case for all column aliases and CTEs.
- **CTE names**: `source`, `unique_source` are the standard names used consistently across models.

### Language

- Code and column names: **English**.
- Comments and documentation: **Spanish** (project owner's language).

### SQL patterns

**Standard staging model structure:**
```sql
with source as (
    select * from {{ source('northwind', '<table>') }}
)
select
    *,
    current_timestamp() as ingestion_timestamp
from source
```

**Standard warehouse model structure (with deduplication):**
```sql
with source as (
    select
        <column_renames_and_casts>,
        current_timestamp() as insertion_timestamp,
    from {{ ref('stg_<model>') }}
),
unique_source as (
    select *,
            row_number() over(partition by <natural_key_columns>) as row_number
    from source
)
select *
except
       (row_number),
from unique_source
where row_number = 1
```

**Key BigQuery-specific syntax used:**
- `SELECT * EXCEPT (column)` — to drop the dedup helper column.
- `current_timestamp()` — for audit timestamps.
- `generate_date_array(...)` — in `dim_date` only.
- `format_date(...)` — BigQuery date formatting.
- Trailing comma after last column in SELECT lists (BigQuery allows it; used throughout).

### Timestamps

- Staging models use: `ingestion_timestamp`
- Warehouse and OBT models use: `insertion_timestamp`

### Partitioning

Fact tables are partitioned by their primary date field:

```sql
{{ config(
    partition_by={
      "field": "<date_column>",
      "data_type": "date"
    }
)}}
```

Currently applied to: `fact_sales` (by `order_date`), `fact_inventory` (by `transaction_created_date`).

### Column prefixing in OBT models

In `obt_*` models, columns from joined dimensions are prefixed with the entity name:
- `c.last_name as customer_last_name`
- `e.last_name as employee_last_name`
- `p.product_name as product_name`

---

## Rules and Restrictions

### Do NOT do this

- **Do not modify `uv.lock` manually.** It is auto-generated by `uv`. Run `uv lock` to regenerate.
- **Do not add new dbt dependencies without reviewing compatibility** with `dbt-core>=1.11.7` and `dbt-bigquery>=1.11.1`.
- **Do not change the BigQuery schema names** (`dl_northwind`, `stg_northwind`, `dwh_northwind`, `obt_northwind`) without updating `dbt_project.yml` and coordinating with the data platform team.
- **Do not use `SELECT *` in warehouse or OBT models** — always explicitly name columns (staging models are the exception, where `SELECT *` is acceptable).
- **Do not use DML (INSERT/UPDATE/DELETE) directly** — all data transformation is handled by dbt materializations.
- **Do not edit `.github/workflows/`** — workflow files require special permissions and should only be changed with explicit approval.
- **Do not write BigQuery-incompatible SQL** — this project is 100% BigQuery; avoid ANSI SQL features not supported by BigQuery (e.g., standard `EXCEPT` set operator has different syntax than BigQuery's column exclusion).

### Files that require approval before modifying

- `dbt_project.yml` — changes affect all model materializations and schemas.
- `northwind/models/staging/source.yml` — defines source tables; changes break downstream models.
- `.github/workflows/claude-assistant.yml` — CI/CD configuration.
- `pyproject.toml` — dependency changes must be tested end-to-end.

---

## Useful Commands

All commands should be run from the repository root unless noted.

```bash
# Install Python dependencies (uses uv)
uv sync

# Run all dbt models
cd northwind && dbt run

# Run a specific model
cd northwind && dbt run --select stg_orders

# Run a specific layer
cd northwind && dbt run --select staging
cd northwind && dbt run --select warehouse
cd northwind && dbt run --select analytics_obt

# Run dbt tests
cd northwind && dbt test

# Compile models (no execution, useful for syntax checking)
cd northwind && dbt compile

# Clean dbt artifacts
cd northwind && dbt clean

# Generate and serve dbt docs
cd northwind && dbt docs generate && dbt docs serve
```

---

## Environment Variables / Configuration

dbt connects to BigQuery via a **profile** named `northwind`, defined in `~/.dbt/profiles.yml` (not committed to the repo).

The profile must configure a BigQuery connection. Typical structure:

```yaml
northwind:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth           # or service-account
      project: <gcp-project-id>
      dataset: <default-dataset>
      threads: 4
      timeout_seconds: 300
      location: <region>      # e.g. US, EU
```

**Required for CI/CD:**
- `CLAUDE_CODE_OAUTH_TOKEN` — GitHub secret for Claude Code action.
- `PAT_GITHUB_TOKEN` — GitHub Personal Access Token for the action.
- BigQuery credentials must also be configured in the CI environment (not visible in this repo).

---

## Workflow for Changes

### Branch naming

```
<type>/<short-description>
```

Examples:
- `feat/add-dim-shipper`
- `fix/fact-sales-dedup`
- `refactor/staging-products`

Claude-generated branches follow: `claude/issue-<n>-<date>-<time>`

### Commit format

Use **Conventional Commits**:

```
<type>: <short description>

[optional body]
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

Examples:
- `feat: add dim_shipper dimension model`
- `fix: correct deduplication key in fact_sales`
- `docs: update source.yml with table descriptions`

### PR process

1. Create a branch from `main`.
2. Make changes following the conventions in this file.
3. Run `dbt compile` locally to check for SQL errors before pushing.
4. Open a PR against `main`.
5. Tag `@santieb` for review.

---

## Known Inconsistencies / Ambiguities

These exist in the current codebase. When modifying affected models, prefer the **recommended convention** below:

| Inconsistency | Current state | Recommended |
|---|---|---|
| Timestamp column name | Staging uses `ingestion_timestamp`; warehouse/OBT use `insertion_timestamp` | Keep `ingestion_timestamp` in staging, `insertion_timestamp` in warehouse/OBT |
| `obt_sales_overview.sql` line 13 | `c.fax_number as customer` (alias missing `_fax_number`) | Should be `c.fax_number as customer_fax_number` |
| `obt_customer_reporting.sql` line 12 | Same issue: `c.fax_number as customer` | Should be `c.fax_number as customer_fax_number` |
| `obt_sales_overview.sql` line 22 | `e.last_name as employee_unique_employee_id` (wrong column aliased) | Should reference the actual unique ID field |
| Dedup key in `fact_sales` | Partition key in `row_number()` includes `shipper_id` twice | Remove duplicate `shipper_id` from partition clause |
| `tests/`, `seeds/`, `macros/`, `analyses/` | All empty (only `.gitkeep`) | Add dbt tests in `tests/` as models grow |
