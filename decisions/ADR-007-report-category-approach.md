# ADR-007: Report and category-query approach — set-based with window functions

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

Adwoa's weekly customer-spending report takes ~40 minutes and sometimes doesn't finish. It needs: total spent, order count, monthly spend for trailing 12 months, running per-customer total (currently tracked by hand), and top-100 ranking — all in seconds on an ordinary laptop. The category rollup needs low-stock visibility through the nested category tree (Electronics → Phones → Phone Accessories → Cases) in a couple of seconds, without hard-coding tree depth. The database runs on a plain PostgreSQL server with no new infrastructure or budget.

## Decision

Replace repeated per-customer subqueries with set-based aggregation and window functions: read the qualifying orders **once**, group them by customer and month, then compute running totals and the rank with window functions. Add indexes that support customer/date order lookups, order-item joins, product/category lookups, and inventory history. Keep the report on the existing PostgreSQL server.

**Measured** ([performance_before_after.md](../evidence/performance_before_after.md), all 40,420 customers, laptop):

| | No indexes | With indexes |
|---|---:|---:|
| Old-style per-customer report | 552 s (9.2 min) | 1.1 s |
| New set-based report | 3.0 s | 2.7 s |

The root cause was the missing index on `orders.customer_id`, combined with a query shape that re-reads all orders for every customer (~19 billion row visits). Either fix alone brings the time to seconds. The rewrite is kept because the old shape is also *wrong* (it counts cancelled/refunded/pending money and has no cutoff, no zero-filled months and no lifetime running total), and because the rewrite's speed does not depend on an index.

The category rollup uses a recursive CTE that:
- Recurses from roots without assuming a fixed depth
- Tracks visited categories to stop cycles
- Reports unreachable categories separately

Do not silently reparent the Seasonal Promotions/Promotions cycle or the Clearance category with its missing parent.

The brief does not define the low-stock cutoff. Use a default threshold of 10 units, exposed as a report parameter so Nana's team can change it. Reachable categories include their reachable descendants; unreachable categories are shown with direct-product counts only, and uncategorized/orphaned products receive a separate row.

## Alternatives considered

### Alternative A: Materialized view refreshed nightly

- **How it would work:** Pre-compute the report as a materialized view, refreshed on a schedule.
- **Why it is attractive:** Fastest reads; report is instant.
- **Why rejected:** It solves a problem we no longer have. The live report takes ~3 seconds and runs once a week, so pre-computing it saves 3 seconds while adding a refresh job someone must schedule, monitor and remember after handover. A forgotten refresh is worse than a slow report: it silently shows last week's numbers as if they were current. Revisit only if the live report ever exceeds the budget.

### Alternative B: ltree extension (materialized path for categories)

- **How it would work:** Install the `ltree` extension, store category paths as materialized paths.
- **Why it is attractive:** O(1) category lookups; no recursion needed.
- **Why rejected:** Requires installing an extension — may violate the "no new tooling" constraint. Recursive CTE works without any extension.

### Alternative C: Closure table for categories

- **How it would work:** Maintain a separate table of all ancestor-descendant pairs.
- **Why it is attractive:** O(1) rollup reads.
- **Why rejected:** Doubles storage and requires complex maintenance on every category insert/update/delete. Overkill for 94 categories.

### Alternative D: Nested sets for categories

- **How it would work:** Store left/right bounds per category; rollup is a range query.
- **Why it is attractive:** Very fast reads.
- **Why rejected:** Expensive writes — inserting one category renumbers half the tree. Marketing keeps adding subcategories, so writes are frequent.

### Alternative E: Bigger server

- **How it would work:** Purchase a more powerful PostgreSQL server.
- **Why it is attractive:** Brute-force solution; no code changes.
- **Why rejected:** It attacks the wrong thing. The old report did ~19 billion row visits because of a missing index; a faster CPU makes each visit a little cheaper, not fewer, so minutes would stay minutes and keep growing with every new customer. The measured fix (an index, or the rewrite) gets seconds on a laptop at no cost. It would also break Nana's "no new monthly bill" constraint.

## Consequences

- **What this buys:** Report runs in seconds on existing hardware. Category rollup handles arbitrary depth, cycles, and orphans gracefully.
- **What this costs:** Complex SQL (window functions, recursive CTEs) that Nana's team must maintain. Six new indexes add a little work to every insert. That is negligible at 4,000 orders/day and measured as harmless under the 400-buyer race test.
- **What it costs the client if I am wrong:** If the status or amount rules are wrong (ADR-003/004), the report is fast and wrong, which is why those rules are explicit and one line each to change. Speed does not depend on the indexes (3.0 s without them), so a dropped index won't bring back 9-minute Mondays.
- **What would make me revisit this:** If window functions can't meet the latency target even with proper indexes, consider a materialized view with incremental refresh.

## What this survives

Growth: the set-based report's cost grows with the number of orders, not customers × orders, so doubling both roughly doubles a ~3 s report rather than quadrupling a 9-minute one. Tree growth: a rolled-back demo adds a 5th category level; a fixed 4-level join silently loses a product (1,931 → 1,930), while the recursive rollup keeps all 1,931 ([06_rollup_depth5_demo.sql](../sql/00_baseline/06_rollup_depth5_demo.sql)). The rollup runs in ~4 ms. Flash sales don't touch the report directly: it reads committed data and takes no locks that block `place_order`.<|end|>