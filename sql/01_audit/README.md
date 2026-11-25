# Kloud Kart Data Audit Queries

This directory contains the data diagnosis queries, broken into focused files by category:

| File | Covers |
|------|--------|
| `01_nulls.sql` | NULLs in primary keys and critical columns |
| `02_duplicates.sql` | Duplicate primary keys |
| `03_stock_issues.sql` | Negative stock, zero/negative quantities, extreme inventory changes, zero-stock products sold |
| `04_referential_integrity.sql` | Orphaned orders, order_items/orders/inventory_log referencing missing parents |
| `05_category_issues.sql` | Missing/self-referencing parents, products without category, category tree depth and cycles |
| `06_customer_issues.sql` | Duplicate customer emails |
| `07_financial_issues.sql` | Order `total_amount` mismatches vs line-item sums |
| `08_data_quality.sql` | Distinct order statuses, future order dates, future inventory_log dates |

## How to run

From inside the Postgres container:

```powershell
docker exec kloudkart-db psql -U postgres -d kloudkart -f /audit/01_nulls.sql
```

Or run all in sequence:

```powershell
for /f %i in ('dir /b audit\*.sql') do docker exec kloudkart-db psql -U postgres -d kloudkart -f /audit/%i
```

Results are written up in `docs/01_data_diagnosis.md`, ranked by danger with detection method and business cost for each finding.
