# Reporting

These reporting functions are installed after the source load and scripts in
`sql/02_schema_changes/`. The data-quality exceptions report is documented in
[`../05_improvement/README.md`](../05_improvement/README.md).

## Customer spending report

Install the function:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/04_reporting/customer_spending_report.sql
```

Run for the supplied extract's as-of date:

```sql
SELECT *
FROM public.customer_spending_report(DATE '2026-08-31');
```

The function returns every customer, including customers with no qualifying orders. It includes lifetime spend/order count through the as-of date, twelve calendar-month spend values with a cumulative total across that 12-month window, deterministic rank by lifetime spend (customer ID breaks ties), and an `is_top_100` flag. The default as-of date is `2026-08-31`. Orders that reference missing customers cannot be attributed and are excluded from customer rows; the data-quality exceptions report surfaces those orphans.

Per ADR-003 and ADR-004, it counts normalized `completed`, `complete`, and `shipped` statuses and sums the recorded `orders.total_amount`. Other statuses are excluded. The query makes that rule explicit; it does not repair stored statuses or totals.

## Low-stock category rollup

Install the function:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/04_reporting/low_stock_rollup.sql
```

Run with the default or a different threshold:

```sql
SELECT * FROM public.low_stock_rollup();
SELECT * FROM public.low_stock_rollup(5);
```

The default threshold is **10 units**. This is an assumption because the brief does not define “low stock”; the caller can supply a different nonnegative threshold.

Reachable categories show counts and stock units for their own low-stock products and all reachable descendants. Categories outside the root-based tree are shown separately with direct-category counts only and marked unreachable. Products with a NULL or missing category are shown in a separate row. The recursive traversal has a visited-ID guard and does not assume a fixed tree depth.
