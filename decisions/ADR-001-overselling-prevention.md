# ADR-001: Overselling prevention via atomic conditional update

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

Kloud Kart oversold its best-selling product twice last month. Two orders landed at the same moment, both took the same last unit, and customers paid for stock that didn't exist. The race_test.py concurrency test fires two simultaneous attempts to buy the last unit and expects exactly one success and one "out of stock" response. The existing schema has no row-level locking, no transactional stock check, and no constraint preventing negative stock. Flash sales will bring ~400 orders in 10 seconds on a single product.

## Decision

Make one database function the only supported path for placing an order. It atomically decrements stock only when the requested quantity is positive and sufficient stock exists:

```sql
UPDATE products
SET stock_quantity = stock_quantity - p_quantity
WHERE product_id = p_product_id
  AND p_quantity > 0
  AND stock_quantity >= p_quantity
RETURNING stock_quantity;
```

If no row is returned, the function reports failure without creating an order, order item, or inventory movement. If stock is available, all three writes happen in the same transaction. The function uses the signature and response contract required by race_test.py.

## Alternatives considered

### Alternative A: SELECT ... FOR UPDATE then check in application code

- **How it would work:** Lock the product row, read stock_quantity, decide in application code, then UPDATE. All in one transaction.
- **Why it is attractive:** Simple to reason about; familiar pattern.
- **Why rejected:** Holds the row lock longer because the check happens in application code between the SELECT and UPDATE. Under 400 concurrent orders in 10 seconds, lock contention and wait time increase. The conditional UPDATE collapses check-and-decrement into one atomic operation.

### Alternative B: SERIALIZABLE isolation level

- **How it would work:** Run the entire order transaction at SERIALIZABLE isolation. PostgreSQL detects conflicts and aborts conflicting transactions.
- **Why it is attractive:** Correct by construction; no explicit locking needed.
- **Why rejected:** Serialization failures require retry logic in the application. Under high concurrency, retry storms can degrade throughput. The conditional UPDATE achieves the same correctness without retries.

### Alternative C: Advisory locks (pg_advisory_lock)

- **How it would work:** Acquire a per-product advisory lock before checking and decrementing stock.
- **Why it is attractive:** Avoids row-level lock contention; can be faster in some scenarios.
- **Why rejected:** Adds complexity (lock management, deadlock risk if ordering is wrong). Provides no advantage over the conditional UPDATE, which already serializes per-product via the row lock.

### Alternative D: Triggers alone (what Nana was told might fix it)

- **How it would work:** A BEFORE INSERT trigger on `order_items` checks stock and raises an exception if it is insufficient.
- **Why it is attractive:** Centralizes logic in the database; application code stays simple.
- **Why rejected:** A trigger is only *where* code runs. Whether it prevents overselling depends on what the code inside does:
  - A trigger that does `SELECT stock_quantity ...` and then decides has exactly the race Nana already has. Under READ COMMITTED, two transactions both read `1`, both pass, and both insert. Triggers get no special isolation.
  - A trigger that does the conditional `UPDATE ... WHERE stock_quantity >= qty` *would* work, but then the atomic update is the fix and the trigger adds nothing except a less obvious place to find it.
  - A trigger signals failure by **raising an exception**. The contract requires a clean `success = false, "out of stock"` that the caller can tell apart from a crash, and race_test.py counts a raised error as a failure. A function can return that answer; a trigger cannot.
  - `CHECK (stock_quantity >= 0)` alone has the same problem. It stops stock going negative, but the losing buyer gets a constraint-violation error instead of "out of stock". We keep the check (as `NOT VALID`) as a backstop, not as the mechanism.
- **Where triggers *are* the right tool:** logging stock changes that bypass the approved functions. A trigger sees every UPDATE however it was issued; see [ADR-002](ADR-002-stock-movements-legacy.md).

## Consequences

- **What this buys:** Exactly one buyer gets the last unit; the other gets an instant, clear "out of stock." No overselling. Works under flash-sale volumes.
- **What this costs:** All order placement must go through this function — direct INSERT into orders/order_items is unsupported.
- **What it costs the client if I am wrong:** If the conditional UPDATE has a bug (e.g., wrong WHERE clause), overselling returns silently. Mitigation: race_test.py runs unmodified against the function.
- **What would make me revisit this:** If flash-sale volumes exceed what row-level locking can handle (lock waits > target latency), consider partitioning by product or using a separate inventory service.

## What this survives, and what it doesn't

**Measured:** race_test.py Test 2 sends 400 simultaneous buyers at 50 units of one product. Result: exactly 50 sold, 350 told "out of stock", 0 errors. The whole burst finished in **~2.7–3.4 s** across recorded runs (the higher figure includes the stock-logging trigger from ADR-002). Marketing's flash-sale forecast is 400 orders in **10 seconds**, so the database finishes the burst in about a third of the window. See [race_test_runs.md](../evidence/race_test_runs.md).

**Why it holds:** every buyer of the same product queues on that product's row lock. Each order holds the lock only for one UPDATE plus three small INSERTs, then commits. Buyers of *different* products don't wait for each other at all. A refused buyer waits only for the lock, then gets an immediate "out of stock"; nothing is retried.

**Limits, in the order they would bite on flash-sale day:**
1. **Connections, not locks.** 400 buyers at once means 400 database connections. PostgreSQL's default limit is 100; past it, buyers get "too many clients", which is a crash, not "out of stock". Docker Compose now sets `max_connections = 500` ([ADR-009](ADR-009-connection-limit.md)). The real fix for production is a small connection pool in the application, so 400 shoppers share ~20–50 connections and queue in the app instead of failing.
2. **One hot row.** All buyers of one product queue on one row. At ~3 s per 400 orders that is ~130 orders/s for a single product on a laptop. That is ample for the forecast, but it's a ceiling: a sale 10× bigger on one product would need stock split into buckets, or a reservation queue.
3. **Checkout integration.** The protection exists only if checkout calls `place_order`. An application that still writes to `orders` directly bypasses it. The stock-logging trigger would at least record such changes, but it cannot refuse them.

**What a naive build would have cost later:** a read-then-write check in application code (or in a trigger) passes every normal-traffic test. It fails only under contention, which means it fails on flash-sale day: the highest-traffic, highest-visibility moment, when overselling the headline product costs the most refunds and reviews.