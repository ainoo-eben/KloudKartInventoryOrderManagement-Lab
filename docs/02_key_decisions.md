# 02 Key Decisions

These decisions guide the SQL implementation. They are based on the [lab brief](../lab-brief.txt), the [data diagnosis](./01_data_diagnosis.md), and the baseline tests. Where the source data cannot settle a business rule, the assumption and its risk are stated.

## 1. Preventing oversells

**Decision:** Make one database function the only supported path for placing an order. It will atomically decrement stock only when the requested quantity is positive and sufficient stock exists:

```sql
UPDATE products
SET stock_quantity = stock_quantity - p_quantity
WHERE product_id = p_product_id
  AND p_quantity > 0
  AND stock_quantity >= p_quantity
RETURNING stock_quantity;
```

If no row is returned, the function reports failure without creating an order, order item, or inventory movement. If stock is available, all three writes happen in the same transaction. The function will use the signature and response contract required by the supplied `race_test.py`.

**Would triggers alone have fixed it? No.** A trigger is only *where* code runs; it gets no special protection from the race. A trigger that reads stock and then decides has exactly the race Nana already has: two transactions both read "1 left". A trigger that does the conditional update would work, but then the conditional update is the fix. A trigger can also only refuse by raising an error, and Nana's requirement (and race_test.py) is a clean "out of stock" answer that the checkout can tell apart from a crash. Triggers *are* used, for the job they're good at: recording stock changes that bypass the approved functions (section 2). Full reasoning: [ADR-001](../decisions/ADR-001-overselling-prevention.md), Alternative D.

**Measured behavior:** race_test.py passes unmodified: 25/25 last-unit races with exactly one winner; 400 buyers for 50 units gives exactly 50 sold, 350 "out of stock", 0 errors, in ~3 seconds; an over-sized order is refused with stock untouched; every sale has its movement. Evidence: [race_test_runs.md](../evidence/race_test_runs.md).

**Flash-sale day:** the database finishes a 400-order burst in about a third of marketing's 10-second window. The first limit is **connections**, not locks: 400 shoppers means 400 connections, and PostgreSQL's default allows 100. Compose now sets 500 for the test; production checkout should use a connection pool ([ADR-009](../decisions/ADR-009-connection-limit.md)).

## 2. Stock movements and legacy stock

**Decision:** Every new stock change is logged in the same transaction as the change:

- **Sales:** `place_order` writes a `sale` movement referencing the order.
- **Restocks, returns, corrections, damage, stock takes:** `adjust_stock(product, change, reason, note)` validates the reason and its sign, requires a note for corrections, refuses anything that would take stock below zero, and logs the movement.
- **Anything else** (a manual `UPDATE`, an old script): a safety-net trigger on `products` logs it as `unlogged_direct_update` with the database user and application, and the exceptions report lists it for follow-up.
- **New products** get an `opening_stock` movement, so their stock always equals the sum of their log.

A trigger alone was rejected because it can see *that* stock changed but not *why*. A function alone was rejected because one forgotten script recreates today's gaps silently. See [ADR-002](../decisions/ADR-002-stock-movements-legacy.md).

Existing history will not be rewritten or “balanced” by guessed adjustments.

The current extract has 14 negative stock quantities and 144 products whose current stock differs from the sum of logged changes. The log does not establish a trusted opening-stock baseline. Therefore:

- Do not set negative quantities to zero or manufacture opening movements.
- Treat the 144 comparisons as unresolved until a trusted opening count or other baseline is supplied.
- Add a non-validating `stock_quantity >= 0` check so existing rows remain loadable while new writes cannot create negative stock; validate it after the legacy negatives are reconciled.
- Keep the order function's conditional stock check, so a product with negative or insufficient stock cannot be sold.

For new order, item, and log IDs, add sequences initialized above the current maximum IDs. Do not allocate IDs using `max(id) + 1`, which can collide under concurrent orders.

## 3. Order statuses used by the spending report

**Decision:** Compare `lower(trim(status))` and map the observed labels as follows:

| Stored values after normalization | Report category | Count as spending? |
|---|---|---|
| `completed`, `complete` | completed | Yes |
| `shipped` | shipped | Yes |
| `pending` | pending | No |
| `cancelled`, `canceled` | cancelled | No |
| `refunded` | refunded | No |

This treats `complete` as a spelling variant of `completed` and assumes a shipped order represents a sale. Pending, cancelled, and refunded orders are excluded. The extract cannot prove whether shipped orders were paid or whether refunds can be partial; if those assumptions are wrong, customer totals will be misstated. Keep the mapping explicit in the report rather than relying on exact-case string comparisons.

Do not merge customer records based on email. Use `customer_id` as the report identity; the 533 normalized duplicate-email groups need investigation before any customer-level merge.

## 4. Amount used for customer spending

**Decision:** Use `orders.total_amount` as the best available checkout amount, applying the status rule above. The schema describes it as written at checkout, so it may include order-level fees or discounts that are absent from receipt lines.

This is a provisional source-of-truth choice, not a claim that every stored total is correct. There are 2,426 differences between order totals and receipt-line sums, 148 receipt lines with NULL prices, and no common numeric difference that explains the mismatches. Do not overwrite either amount from the other. Expose the mismatch count as a data-quality warning and revisit the choice if checkout, delivery-fee, discount, or payment records become available.

Zero-priced receipt lines are allowed as possible free gifts; no negative line prices were found. New receipt lines must have a price, but zero remains valid. Existing NULL prices should be preserved and flagged rather than filled with today's product price, which may have changed.

## 5. Reporting date range

**Decision:** For this supplied extract, use **2026-08-31** as the reporting as-of date and flag orders dated September 1, 2026 or later. August contains 36,357 orders; later-dated rows are suspect relative to the apparent extract boundary.

Make the as-of date an explicit report parameter. Do not permanently hard-code August 2026 into an operational report; use a later date only after the later records are verified. This avoids silently including questionable future-dated rows in this dataset's report.

## 6. Legacy rows and constraints

**Decision:** Preserve the supplied records and avoid guessed repairs. Existing orphaned references mean some foreign keys cannot be validated immediately. Add appropriate foreign keys as `NOT VALID` where legacy rows violate them, so new writes are checked while old exceptions remain visible. Validate them only after a documented cleanup.

Known examples include missing customers on orders, missing orders on order items, missing products on inventory-log rows, and broken category references. Do not add a unique email constraint while normalized duplicate groups remain.

For future rows, require positive order quantities and non-NULL, non-negative receipt prices. Allow zero prices because they may represent gifts. Keep status normalization in the report until legacy labels are reviewed; do not silently rewrite the historical statuses.

## 7. Report and category-query approach

**Decision:** Replace repeated per-customer subqueries with set-based aggregation and window functions. Add indexes that support customer/date order lookups, order-item joins, product/category lookups, and inventory history. Keep the report on the existing PostgreSQL server; do not solve the performance issue by buying a larger server or adding infrastructure.

**Measured before/after** (all 40,420 customers, laptop; [performance_before_after.md](../evidence/performance_before_after.md)):

| | No indexes | With indexes |
|---|---:|---:|
| Old-style per-customer report | **552 s (9.2 min)** | 1.1 s |
| New set-based report | **3.0 s** | 2.7 s |

**What actually made it slow:** the old shape re-reads all 159,384 orders for each of 40,420 customers, three times over (~19 billion row visits), because there is no index on `orders.customer_id`. Either fix alone gets to seconds. I keep **both**: the index, because one-customer lookups need it, and the rewrite, because the old shape is also wrong (it counts GHS 106M of cancelled/refunded/pending orders, has no cutoff and skips empty months) and its speed would hinge entirely on that one index surviving future changes. **Would the bigger server have fixed it?** No. A faster CPU doesn't reduce 19 billion row visits, and the time would keep growing with every new customer.

I don't claim a multiplier against Adwoa's "40 minutes": her query wasn't supplied, and the stand-in ran 9.2 minutes on this laptop. The honest claim is minutes → ~3 seconds.

The category rollup will recurse from roots without assuming a fixed depth, track visited categories to stop cycles, and report unreachable categories separately. Use a default low-stock threshold of **10 units**, exposed as a parameter because the brief does not define the cutoff. Unreachable categories show direct-product counts only; uncategorized products are reported separately. Do not silently reparent the `Seasonal Promotions`/`Promotions` cycle or the `Clearance` category with its missing parent.

## 8. Improvement beyond the brief

**Decision:** Add a data-quality exceptions report for status variants, order/line total differences, missing prices, orphan references, suspect dates, negative stock, and stock/log reconciliation. It gives Nana and Adwoa a recurring way to see when report inputs need review instead of discovering surprises in a weekly ranking.

Stock/log exceptions must remain marked **unverified** until a trusted opening-stock baseline is established. This report must surface exceptions, not silently change business data. It now also lists every stock change made outside the approved process (`stock_changed_outside_approved_process`), so the audit trail stays honest after handover.

## 9. What "running per-customer total" means

**Decision:** The brief doesn't say whether Adwoa's running total is cumulative within the 12-month view or since the customer's first order. Each month in the report carries **both**: `running_spend` (within the 12 months) and `lifetime_running_spend` (since the first order; the final month always equals `total_spent`). On this extract they differ for 1,602 customers who bought before the 12-month window. Providing both costs one extra number per month, whereas guessing wrong would mean Adwoa keeps her hand-kept spreadsheet. The validation script checks that the final lifetime figure equals `total_spent` for every customer.

## 10. Connection limit for flash-sale traffic

**Decision:** `docker-compose.yml` sets `max_connections=500`, so the supplied 400-buyer test passes on a fresh container without manual steps. For production, recommend a connection pool in the checkout application rather than one connection per shopper. PgBouncer was rejected as new infrastructure. See [ADR-009](../decisions/ADR-009-connection-limit.md).

## 11. Judgement calls and what they cost Nana if wrong

| # | Decision | If I'm wrong, Nana pays… | How he'd find out | Reversible? |
|---|---|---|---|---|
| 1 | Atomic conditional update in `place_order`, not triggers | Overselling returns, silently | race_test.py runs unmodified; rerun it after any change | Yes |
| 2 | Log every stock change (functions + safety-net trigger) | An extra check on each stock update; staff must give reasons | Exceptions report shows `unlogged_direct_update` rows | Yes |
| 3 | `completed`, `complete`, `shipped` count as spend | Up to GHS 314M of spend misclassified; wrong top-100 | Business confirms status meanings; one-line change in the report | Yes |
| 4 | `orders.total_amount` is the money figure | GHS 5.2M of order/receipt-line differences go the other way | Compare against payment records | Yes, one column |
| 5 | Cutoff 2026-08-31; later rows held back | GHS 68,040.02 of real orders left out if they're genuine | Check the 24 orders against source records | Yes, parameter |
| 6 | Legacy data preserved; constraints `NOT VALID` | Bad old rows remain until cleaned | Exceptions report lists each one | Yes |
| 7 | Low-stock threshold = 10 units | Alerts too late or too noisy for fast movers | Adwoa/ops feedback | Yes, parameter |
| 8 | Don't merge duplicate-email customers | GHS 9.7M of spend may be split across 1,068 rows | Manual review of the 533 groups | Yes |
| 9 | `max_connections` 500 + recommend app pool | Errors (not oversells) at flash-sale peak if no pool is added | Load test checkout before the sale | Yes |
| 10 | Both running-total readings provided | Nothing material | — | — |

## 12. What a naive build would have cost later

- **Overselling:** a check-then-update (in code or a trigger) passes every normal-day test and fails only under contention, which means on flash-sale day, on the headline product, at peak visibility.
- **Report:** buying the bigger server Nana was quoted would not have fixed a query that re-reads all orders for every customer (~19 billion row visits; 9.2 minutes measured). The cost grows with customers × orders, so it would have slowed again as the business grew, on a bigger monthly bill. The real cause was a missing index plus that query shape; fixing either gets to seconds (section 7).
- **Category rollup:** a fixed four-level join is correct *today* (the tree is exactly four deep) and silently drops products the day marketing adds a fifth level. Nobody would notice until a stock-out.
- **Statuses:** an exact `status = 'completed'` filter looks right and runs fast, and misses GHS 314M of real spend.
