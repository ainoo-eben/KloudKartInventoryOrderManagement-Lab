# ADR-007: Report and category-query approach — set-based with window functions

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

Adwoa's weekly customer-spending report takes ~40 minutes and sometimes doesn't finish. It needs: total spent, order count, monthly spend for trailing 12 months, running per-customer total (currently tracked by hand), and top-100 ranking — all in seconds on an ordinary laptop. The category rollup needs low-stock visibility through the nested category tree (Electronics → Phones → Phone Accessories → Cases) in a couple of seconds, without hard-coding tree depth. The database runs on a plain PostgreSQL server with no new infrastructure or budget.

## Decision

Replace repeated per-customer subqueries with set-based aggregation and window functions. Add indexes that support customer/date order lookups, order-item joins, product/category lookups, and inventory history. Keep the report on the existing PostgreSQL server.

The category rollup uses a recursive CTE that:
- Recurses from roots without assuming a fixed depth
- Tracks visited categories to stop cycles
- Reports unreachable categories separately

Do not silently reparent the Seasonal Promotions/Promotions cycle or the Clearance category with its missing parent.

## Alternatives considered

### Alternative A: Materialized view refreshed nightly

- **How it would work:** Pre-compute the report as a materialized view, refreshed on a schedule.
- **Why it is attractive:** Fastest reads; report is instant.
- **Why rejected:** Stale during the day. Nana needs current data for decisions. Also adds refresh complexity and storage.

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
- **Why rejected:** Nana's constraint: no new infrastructure, no monthly bill. The brief explicitly says "someone already priced a bigger server; neither guess has convinced him."

## Consequences

- **What this buys:** Report runs in seconds on existing hardware. Category rollup handles arbitrary depth, cycles, and orphans gracefully.
- **What this costs:** Complex SQL (window functions, recursive CTEs) that Nana's team must maintain. Performance depends on proper indexes.
- **What it costs the client if I am wrong:** If indexes are missing or wrong, the report is still slow. Mitigation: before/after timing measurements documented in a measurement report.
- **What would make me revisit this:** If window functions can't meet the latency target even with proper indexes, consider a materialized view with incremental refresh.

## What this survives

Flash-sale volumes (~400 orders in 10 seconds). The set-based approach scales with data size, not with per-customer query count. The recursive CTE handles any tree depth marketing adds.<|end|>