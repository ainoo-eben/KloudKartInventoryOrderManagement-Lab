# Kloud Kart Data Audit Queries

This directory contains the data diagnosis queries, broken into focused files by category:

| File | Covers |
|------|--------|
| `01_nulls.sql` | NULLs in primary keys and critical columns |
| `02_duplicates.sql` | Duplicate primary keys |
| `03_stock_issues.sql` | Negative stock, historical sales for products currently at zero stock, stock/log comparison, and inventory-log reasons/signs |
| `04_referential_integrity.sql` | Orphaned orders, order_items/orders/inventory_log referencing missing parents |
| `05_category_issues.sql` | Missing/self-referencing parents, products without category, category tree depth and unreachable category names |
| `06_customer_issues.sql` | Duplicate customer emails, including case/space-normalized duplicates |
| `07_financial_issues.sql` | Order total differences, difference patterns, and missing/non-positive prices |
| `08_data_quality.sql` | Exact order-status counts and totals, dates after the August 2026 cutoff, and orders predating customer registration |

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
