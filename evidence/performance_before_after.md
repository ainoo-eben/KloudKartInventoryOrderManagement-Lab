# Performance: before and after

Generated with [scripts/benchmark.ps1](../scripts/benchmark.ps1) (`-FullNaiveBaseline`). Raw output: [benchmark_raw.txt](benchmark_raw.txt).

- **Machine:** Intel Core i7-1165G7 (laptop, 4 cores / 8 threads), 31.7 GB RAM, Docker Desktop, PostgreSQL 16.16.
- **Data:** the supplied extract, freshly loaded into a disposable database (40,420 customers, 159,384 orders).
- **Method:** `EXPLAIN ANALYZE` execution time, median of 3 runs (the full 9-minute baseline ran once).

## Monday customer report

The "before" query is a representative stand-in for Adwoa's report: Adwoa's original SQL was not supplied. It computes, for **every customer**, total spend, order count, and a monthly breakdown with a running total, using three per-customer sub-queries, which is the common hand-written shape. It returns every customer (no `LIMIT`), the same row count as the new report.

| Query | Schema | Time (all 40,420 customers) |
|---|---|---:|
| Old-style report | As supplied (primary keys only) | **552.2 s (9.2 min)**, measured once to completion |
| Old-style report | + indexes (`03_indexes.sql`) | **1.12 s** |
| New report (`customer_spending_report`) | As supplied, no indexes | **3.04 s** |
| New report | + indexes | **2.68 s** |

Sample runs on the original schema confirm the old query's cost grows **linearly with customers**: 500 → 7.3 s, 1,000 → 14.7 s, 2,000 → 29.3 s (~14.7 ms per customer). The extrapolation to all customers (~593 s) is close to the measured 552 s.

### What this shows, honestly

1. **The root cause was a missing index, not the server.** Without an index on `orders.customer_id`, each of the three sub-queries reads all 159,384 orders, for every one of 40,420 customers: about 19 billion row visits. Adding the index alone takes the old query from **9.2 minutes to about 1 second**. A bigger server would have made each of those 19 billion visits slightly faster, not fewer.
2. **The rewrite alone also fixes it.** With no new index at all, the set-based report reads the orders **once** and finishes in about **3 seconds**, roughly 180× faster than the old shape. Its time grows with the number of orders, not customers × orders.
3. **Why keep the rewrite when "old query + index" is faster?** Because the old query gives the wrong answer quickly:
   - it counts cancelled, refunded and pending orders as spend (GHS 106M on this extract; see the diagnosis, finding 3);
   - it has no reporting cutoff, so suspect post-August orders leak in;
   - its monthly breakdown skips months with no purchases, so a customer's 12 months are not comparable;
   - it has no lifetime running total and no top-100 rank over everyone.

   The new report does all of that, covers 12 zero-filled months for every customer (485,040 customer-months) and *still* takes under 3 seconds. Its speed does not depend on an index that someone could later drop.
4. **The indexes stay**, for what they *are* needed for: looking up one customer's orders (support, Adwoa's ad-hoc checks), order items by order, products by category, and stock history by product.

The brief's "about 40 minutes" was Adwoa's experience on her setup with her query. The stand-in measured 9.2 minutes on this laptop. The two are not the same query or machine, so the honest claim is **"minutes → about 3 seconds"**, not a specific multiplier against her 40 minutes.

## Low-stock category rollup

| Query | Time | Correct on today's 4-level tree? | Correct after marketing adds a 5th level? |
|---|---:|---|---|
| Fixed 4-level self-join ([05_naive_rollup_fixed_depth.sql](../sql/00_baseline/05_naive_rollup_fixed_depth.sql)) | 1.8 ms | Yes | **No**: drops the product |
| Recursive `low_stock_rollup(10)` | 3.7 ms (3.9 ms with indexes) | Yes | **Yes** |

Both are far inside Nana's "couple of seconds", so speed is not the issue here; **correctness as the tree grows** is. [06_rollup_depth5_demo.sql](../sql/00_baseline/06_rollup_depth5_demo.sql) adds a 5th-level subcategory, moves one low-stock product into it, and rolls back:

| Low-stock products counted across root categories | Before | After adding level 5 |
|---|---:|---:|
| Recursive rollup | 1,931 | **1,931** |
| Fixed-depth rollup | 1,931 | **1,930** (one product silently lost) |

The recursive version also tracks visited categories, so the Promotions ↔ Seasonal Promotions loop (9001/9002) can't make it run forever. It reports those categories, and the orphan Clearance category, as unreachable rather than hiding them.

## Flash-sale order placement

From race_test.py (unmodified): 400 simultaneous buyers, 50 units, exactly 50 sold, 0 errors, **~2.7–3.4 s** wall clock across runs (see [race_test_runs.md](race_test_runs.md) and [final_validation.md](final_validation.md)).
