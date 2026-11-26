# Before Report Plan and Timing

## What this measures

This is a representative performance proxy, not Adwoa's original report. It sums recorded `orders.total_amount` across all statuses. Those choices are for timing only; they do not establish which statuses count as spend or which amount is financially authoritative.

## Estimated plan

- Customers scanned: **40,420**
- Output: the top 100 customers, sorted by recorded spend.
- The query runs three correlated subqueries per customer.
- Each subquery scans `orders` by `customer_id`; the original schema has no index on that column.
- The monthly subquery also scans orders by customer and date.
- Estimated total plan cost: **627,009,541.97 planner cost units**. Planner cost is not elapsed time.

## Actual execution attempt

`EXPLAIN ANALYZE` ran with a 120-second statement timeout and was canceled after **00:02:00.2614895**. No actual execution plan or completion time was returned.

This establishes that this representative query did not finish within two minutes. It does not establish its full runtime or reproduce Adwoa's exact 40-minute report.

The full planner output and timeout message are in [explain_before_raw.md](explain_before_raw.md). The query is [02_naive_report.sql](../sql/00_baseline/02_naive_report.sql).