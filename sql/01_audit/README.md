# Kloud Kart Data Audit Queries

This directory contains the data diagnosis queries, broken into focused files by category:

| File | Covers |
|------|--------|
| `01_nulls.sql` | NULLs in primary keys and critical columns |
| `02_duplicates.sql` | Duplicate primary keys |
| `03_stock_issues.sql` | Negative stock, historical sales for products currently at zero stock, stock/log comparison, and inventory-log reasons/signs |
| `04_referential_integrity.sql` | Orphaned orders, order_items/orders/inventory_log referencing missing parents |
| `05_category_issues.sql` | Missing/self-referencing parents, products without category, category tree depth and unreachable category names |
| `06_customer_issues.sql` | Duplicate customer emails: an exact (case-sensitive) count and a case/space-normalized count. They are not comparable; use the normalized one |
| `07_financial_issues.sql` | Order total differences, difference patterns, and missing/non-positive prices |
| `08_data_quality.sql` | Exact order-status counts and totals, dates after the August 2026 cutoff, and orders predating customer registration |
| `09_financial_impact.sql` | GHS at stake for each diagnosis finding (the "GHS at stake" column in `docs/01_data_diagnosis.md`) |

All nine files are read-only and are run, in this order, by `sql/run_all.sql`.

## How to run

Run from the project root in PowerShell after loading the source data. Set
`$DbName` to the disposable database you created using the root README:

```powershell
$DbName = "kloudkart_lab"
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/01_audit/01_nulls.sql
```

To run all audit files in order. The list is explicit (it matches the table
above and `sql/run_all.sql`), so a file added to this folder later is not run
by accident; add it to both lists deliberately:

```powershell
$AuditFiles = @(
    "01_nulls.sql", "02_duplicates.sql", "03_stock_issues.sql",
    "04_referential_integrity.sql", "05_category_issues.sql",
    "06_customer_issues.sql", "07_financial_issues.sql",
    "08_data_quality.sql", "09_financial_impact.sql"
)
foreach ($file in $AuditFiles) {
    docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f "/sql/01_audit/$file"
    if ($LASTEXITCODE -ne 0) {
        throw "Audit failed: $file"
    }
}
```

Results are written up in `docs/01_data_diagnosis.md`, ranked by danger with detection method and business cost for each finding.
