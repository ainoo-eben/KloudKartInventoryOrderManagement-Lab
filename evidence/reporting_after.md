# Reporting Validation and Timing

## Test setup

- Loaded the supplied schema and CSVs into a disposable PostgreSQL database.
- Applied the schema-change scripts and both reporting functions.
- Ran `EXPLAIN (ANALYZE, BUFFERS, TIMING ON)` against each report.
- Dropped the disposable database after testing; the existing `kloudkart` database was not changed.

## Customer spending report

Called `public.customer_spending_report(DATE '2026-08-31')`.

- Customers returned: **40,420**
- Top-100 flags: **100**
- Ranks: **1 through 40,420**
- Rows with anything other than 12 monthly values: **0**
- Qualifying orders included: **124,025**
- Sum of reported lifetime spend: **380,090,162.62**
- PostgreSQL execution time: **3,848.116 ms** (about **3.85 seconds**)

The report uses `orders.total_amount` and includes statuses whose trimmed, lower-case value is `completed`, `complete`, or `shipped`, through the supplied extract cutoff of August 31, 2026. These are the documented provisional business assumptions, not independently verified payment totals.

## Low-stock category rollup

Called `public.low_stock_rollup(10)` using the default 10-unit threshold.

- Output rows: **95** — 91 reachable categories, 3 unreachable categories, and 1 unassigned/missing-category bucket.
- The unreachable rows identify the existing Promotions/Seasonal Promotions cycle and Clearance's missing parent.
- PostgreSQL execution time: **6.110 ms**.

Reachable category counts include their reachable descendants. Summing those counts across all category rows counts a product again at each ancestor level; it is not a distinct-product total across the whole result. Unreachable categories show direct-category products only. Products with NULL or missing category references appear in the separate unassigned bucket.

## Before/after context

The representative baseline query in [explain_before.md](explain_before.md) did not complete within its **120-second** statement timeout. The new report returned the full 40,420-customer result in about **3.85 seconds** on this test setup.

**Superseded by a like-for-like comparison:** see [performance_before_after.md](performance_before_after.md): the full old-style report measured 552 s on the original schema vs ~3 s for the new report, plus an index ablation. The note below described the earlier 120-second-timeout comparison.

This is strong evidence of improvement, but not an exact apples-to-apples speedup: the original was a representative proxy rather than Adwoa's supplied query, the old run was cut off at 120 seconds, and the final report applies the documented status and amount rules.

## Reproduction

Install the functions with [customer_spending_report.sql](../sql/04_reporting/customer_spending_report.sql) and [low_stock_rollup.sql](../sql/04_reporting/low_stock_rollup.sql), then call them as shown in [the reporting README](../sql/04_reporting/README.md).
