# Supplied Race Test Run

- Test: data/race_test.py (unmodified, all tests)
- Isolated database: `kloudkart_race_test_20261126` (removed after run)
- PostgreSQL `max_connections`: temporarily raised from 100 to 450 for the test, then restored to 100
- Result: **PASSED** (exit code 0)

```text
race_test.py — Kloud Kart order placement under contention
==================================================================
  place_order found: place_order(p_customer_id bigint, p_product_id bigint, p_quantity integer)

Test 1 — two buyers, one unit, 25 rounds
  ok    25/25 rounds: exactly one winner, stock 0, one order, no errors

Test 2 — flash sale: 400 buyers, 50 units
        50 sold, 350 refused, 0 errored, wall clock 2.65s
  ok    exactly 50 sold, none oversold, no errors, 2.65s

Test 3 — asking for more than exists
  ok    refused cleanly, stock untouched

Test 4 — audit trail after contention
  ok    5 sold, 5 movements recorded

==================================================================
PASSED — exactly one buyer gets the last unit, every time.
```
