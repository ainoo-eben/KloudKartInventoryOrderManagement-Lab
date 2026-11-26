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

### Alternative D: Triggers alone

- **How it would work:** A BEFORE INSERT trigger on order_items checks stock and raises an exception if insufficient.
- **Why it is attractive:** Centralizes logic in the database; application code stays simple.
- **Why rejected:** A trigger does not make an application-side "read stock, then decide" sequence atomic. Concurrent requests can both pass a stale check. The conditional UPDATE makes the stock test and decrement one database operation; PostgreSQL's row lock serializes competing updates to the same product.

## Consequences

- **What this buys:** Exactly one buyer gets the last unit; the other gets an instant, clear "out of stock." No overselling. Works under flash-sale volumes.
- **What this costs:** All order placement must go through this function — direct INSERT into orders/order_items is unsupported.
- **What it costs the client if I am wrong:** If the conditional UPDATE has a bug (e.g., wrong WHERE clause), overselling returns silently. Mitigation: race_test.py runs unmodified against the function.
- **What would make me revisit this:** If flash-sale volumes exceed what row-level locking can handle (lock waits > target latency), consider partitioning by product or using a separate inventory service.

## What this survives

Flash-sale spikes of ~400 orders in 10 seconds on a single product. The row lock serializes per-product, so throughput is bounded by lock acquisition speed, not by application logic.