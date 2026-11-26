# Data-quality exceptions report — validation

The report was run on a disposable database freshly loaded from the supplied
extract. The as-of date was **2026-08-31**, matching the extract's documented
cutoff. The source files and the existing `kloudkart` database were not
modified.

## Findings

The function returned **3,864 report rows** covering **94,756 affected
records**. Formatting variants are summarized by stored status value rather
than emitted once per order.

| Exception | Report rows | Affected records |
|---|---:|---:|
| Order status formatting variants | 8 | 90,900 |
| Order/receipt-line total differences | 2,426 | 2,426 |
| Order items with no matching order | 692 | 692 |
| Orders with no matching customer | 210 | 210 |
| Inventory movements with no matching product | 120 | 120 |
| Missing receipt-line prices | 148 | 148 |
| Products missing a category | 37 | 37 |
| Orders after the as-of date | 24 | 24 |
| Inventory movements after the as-of date | 40 | 40 |
| Negative product stock | 14 | 14 |
| Stock differs from logged net movement | 144 | 144 |
| Categories with a missing parent | 1 | 1 |

No unknown order statuses or order items with missing products were present in
this extract. A separate transactional check inserted an unknown status,
confirmed the report identified it and its detection query returned the
matching row, then rolled back the test data.

All 144 stock/log differences were marked **unverified** because no trusted
opening-stock baseline is available. All 19 distinct detection queries
returned by the report were executed successfully. The report rejected a
NULL as-of date with the expected error.

## Performance and integration checks

- `EXPLAIN (ANALYZE, BUFFERS)` for the report completed in **1.107 seconds** on
  the disposable database.
- `sql/run_all.sql` successfully loaded the supplied schema and CSVs, ran the
  audits, applied schema changes, and installed all order/report functions.
- The runner was also executed again against the same disposable database,
  confirming its schema reload path works.
- A valid `place_order` smoke test succeeded and created one order, one item,
  and one inventory-log entry.
- The existing `kloudkart` database was left untouched.
