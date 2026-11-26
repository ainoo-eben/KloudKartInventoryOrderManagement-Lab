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

**Why not a trigger alone:** A trigger does not make an application-side “read stock, then decide” sequence atomic. Concurrent requests can both pass a stale check. The conditional update makes the stock test and decrement one database operation; PostgreSQL's row lock serializes competing updates to the same product.

**Expected behavior:** Two buyers racing for one unit produce one success and one clear “out of stock.” A request for more units than available changes nothing. The 400-buyer case will be tested against the actual function before claiming it meets the flash-sale target.

## 2. Stock movements and legacy stock

**Decision:** Every new order will write one negative `sale` movement in `inventory_log` in the same transaction as the stock decrement and order records. Existing history will not be rewritten or “balanced” by guessed adjustments.

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

The category rollup will recurse from roots without assuming a fixed depth, track visited categories to stop cycles, and report unreachable categories separately. Do not silently reparent the `Seasonal Promotions`/`Promotions` cycle or the `Clearance` category with its missing parent.

## 8. Improvement beyond the brief

**Decision:** Add a data-quality exceptions report for status variants, order/line total differences, missing prices, orphan references, suspect dates, negative stock, and stock/log reconciliation. It gives Nana and Adwoa a recurring way to see when report inputs need review instead of discovering surprises in a weekly ranking.

Stock/log exceptions must remain marked **unverified** until a trusted opening-stock baseline is established. This report must surface exceptions, not silently change business data.
