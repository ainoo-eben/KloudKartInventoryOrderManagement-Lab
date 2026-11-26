# 01 Data Diagnosis

Kloud Kart Ltd. data audit results. Every problem found, how it was detected, what it costs Nana if uncorrected, ranked by danger.

---

## Data at a Glance

| Table | Rows |
|-------|------|
| categories | 94 |
| customers | 40,420 |
| inventory_log | 282,352 |
| order_items | 336,559 |
| orders | 159,384 |
| products | 4,023 |

---

## How We Checked (Method)

1. **Fresh load:** Ran `data/schema.sql` then `data/load.sql` into a clean PostgreSQL database.
2. **Ran 8 audit query files** in `sql/01_audit/` — each file targets one class of problem (NULLs, duplicates, stock issues, referential integrity, category tree, customer data, financial data, general quality).
3. **Recorded counts** of offending rows for each check.
4. **Ranked by danger** to Nana's business: Critical → High → Medium → Low.

You can re-run any check yourself:

```bash
docker exec kloudkart-db psql -U postgres -d kloudkart -f /sql/01_audit/01_nulls.sql
# ...and so on for 02_duplicates.sql through 08_data_quality.sql
```

---

## Findings — Ranked by Danger

### 1. Products with negative stock — 14 products (CRITICAL)

**What:** 14 products have `stock_quantity < 0` in the `products` table.

**How to verify:**
```sql
SELECT count(*) FROM products WHERE stock_quantity < 0;
-- To see them:
SELECT product_id, product_name, stock_quantity
FROM products WHERE stock_quantity < 0;
```

**Cost to Nana:** The database believes Kloud Kart owes inventory it doesn't have. These products are already oversold beyond zero. Any new order for them deepens the hole.

---

### 2. Stock does not reconcile to logged movements for 144 products (HIGH, provisional)

**What:** For 144 of 4,023 products, the current `stock_quantity` differs from the sum of all `inventory_log.change_qty` entries for that product. All 4,023 products have at least one log entry. The difference ranges from -56 to +6; there is no single offset explaining the mismatches.

**Important limitation:** This is a reconciliation warning, not proof that 144 current stock counts are wrong. The log has no explicit `opening stock` reason, and the data does not document whether its movements start from zero or include each product's opening balance. Without that baseline, adding all movements and comparing the result to today's count may be invalid.

**Movement reasons and signs:** The log has six exact reason values. Sale, restock, return, and damage signs are consistent with their labels. `correction` includes both positive and negative changes; all `stock_take` entries have a zero change.

| Reason | Entries | Minimum change | Maximum change | Sign observation |
|---|---:|---:|---:|---|
| `sale` | 262,088 | -10 | -1 | All negative |
| `restock` | 18,857 | 13 | 82 | All positive |
| `return` | 564 | 1 | 3 | All positive |
| `correction` | 485 | -8 | 7 | 195 positive; 290 negative |
| `damage` | 268 | -5 | -1 | All negative |
| `stock_take` | 90 | 0 | 0 | All zero |

**How to verify:**
```sql
SELECT count(*) AS products_not_matching_logged_net_change
FROM (
    SELECT p.product_id
    FROM products p
    LEFT JOIN inventory_log il ON il.product_id = p.product_id
    GROUP BY p.product_id, p.stock_quantity
    HAVING p.stock_quantity <> coalesce(sum(il.change_qty), 0)
) mismatches;
```

**Cost to Nana:** If the log is meant to account for all stock from a known starting point, these products cannot be reconciled and their available quantities may be unreliable. Confirm the opening-balance convention before treating this as a proven variance.

---

### 3. Order status spellings can misstate customer spend — 15 values (HIGH)

**What:** `orders.status` is free text. The 159,384 orders use 15 distinct spellings, including capitalization differences, a trailing space, and the separate value `complete`. This directly affects which orders a spending report includes.

**Exact counts by stored value:**

| Stored status | Orders | Sum of recorded `total_amount` |
|---|---:|---:|
| `completed ` (trailing space) | 22,395 | 69,151,925.44 |
| `COMPLETED` | 22,392 | 67,618,128.94 |
| `complete` | 22,285 | 68,086,741.07 |
| `Completed` | 22,188 | 68,271,874.79 |
| `completed` | 22,091 | 66,480,695.79 |
| `Pending` | 8,081 | 24,289,314.93 |
| `pending` | 7,928 | 24,210,317.64 |
| `shipped` | 6,516 | 20,176,735.18 |
| `Shipped` | 6,332 | 20,780,169.69 |
| `Refunded` | 3,262 | 10,354,065.27 |
| `cancelled` | 3,238 | 9,396,828.73 |
| `refunded` | 3,217 | 9,480,017.84 |
| `canceled` | 3,209 | 8,976,160.54 |
| `Cancelled` | 3,131 | 9,559,396.68 |
| `CANCELLED` | 3,119 | 10,231,587.28 |

These are sums of the values stored in `orders.total_amount`, not verified revenue or amounts actually collected.

The four capitalization/spacing forms of `completed` account for 89,066 orders; `complete` is another 22,285 whose intended meaning needs to be confirmed. A report that matches only the exact value `completed` would include just 22,091 orders and omit the variants. A report that includes every status would count cancelled and refunded orders as spend. The data alone does not establish the business meaning of each status, so the reporting rule must be stated explicitly.

**How to verify:**
```sql
SELECT quote_literal(status) || ' [length=' || length(status) || ']' AS exact_status,
       count(*) AS orders
FROM orders
GROUP BY status
ORDER BY orders DESC, exact_status;
```

**Cost to Nana:** This can materially change every customer's reported spend, order count, and ranking—not just make a label look inconsistent. Until the statuses are mapped to clear business meanings, Adwoa's report could silently omit valid purchases or count cancelled/refunded money.

---

### 4. Order totals and receipt lines do not reconcile — 2,426 orders (HIGH)

**What:** 2,426 orders have an `orders.total_amount` that differs from the sum of `order_items.quantity * order_items.unit_price`. Among these, 28 orders have no calculable line total because all of their line prices are NULL. For the other 2,398, there are 2,338 different numeric differences and no difference occurs more than twice. The differences do not point to one consistent delivery fee or discount.

There are also 148 order-item rows with a NULL `unit_price` across 147 orders; a line-total calculation skips those unknown prices. Another 152 rows have a price of zero and none are negative. Zero-priced lines could be free gifts, so they need business context rather than automatic rejection. Product catalogue prices have no NULL, zero, or negative values.

**How to verify:**
```sql
SELECT count(*)
FROM orders o
JOIN (
    SELECT order_id, sum(quantity * unit_price) AS calc_total
    FROM order_items GROUP BY order_id
) i ON i.order_id = o.order_id
WHERE o.total_amount IS DISTINCT FROM i.calc_total;
```

```sql
SELECT count(*) FILTER (WHERE unit_price IS NULL) AS null_prices,
       count(*) FILTER (WHERE unit_price <= 0) AS zero_or_negative_prices
FROM order_items;
```

**Cost to Nana:** The mismatches are real differences, but they do not prove which side is wrong. They could reflect unrecorded fees/discounts, missing line prices, or bad totals. Do not assume either `orders.total_amount` or the receipt lines are authoritative until those rules and missing prices are checked; otherwise customer-spend totals may be wrong.

---

### 5. order_items referencing missing orders — 692 line items (HIGH)

**What:** 692 rows in `order_items` point to an `order_id` that does not exist in `orders`.

**How to verify:**
```sql
SELECT count(*) FROM order_items oi
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = oi.order_id);
```

**Cost to Nana:** These sales are invisible to the orders table. Revenue is understated, customer order counts are wrong, and the audit trail has gaps.

---

### 6. Orders referencing missing customers — 210 orders (HIGH)

**What:** 210 orders point to a `customer_id` that does not exist in `customers`.

**How to verify:**
```sql
SELECT count(*) FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id);
```

**Cost to Nana:** Adwoa cannot attribute spend to a real customer. Top-100 customer ranking and per-customer totals are incomplete. These customers effectively don't exist in the report.

---

### 7. inventory_log referencing missing products — 120 entries (HIGH)

**What:** 120 rows in `inventory_log` point to a `product_id` that does not exist in `products`.

**How to verify:**
```sql
SELECT count(*) FROM inventory_log il
WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = il.product_id);
```

**Cost to Nana:** The audit trail is broken. An auditor walking through stock movements for these products hits dead ends. This violates Nana's requirement for a complete trail of every stock movement.

---

### 8. Dates after the data's August 2026 end point — 24 orders and 40 inventory entries (MEDIUM)

**What:** The dataset's apparent end point is August 2026 (36,357 orders in August). After August 31, 2026, there are 24 orders dated September 2026 through August 2027, and 40 inventory-log entries dated September 2026 through August 2027. This includes September's five orders. These records are suspect relative to the data's end point; they are not validated future business activity.

**How to verify:**
```sql
SELECT count(*) FROM orders
WHERE order_date >= DATE '2026-09-01';

SELECT count(*) FROM inventory_log
WHERE created_at >= DATE '2026-09-01';
```

**Cost to Nana:** Monthly reports can include transactions beyond the apparent period covered by the extract, making the latest months misleading without an obvious error. The inventory notebook's timeline can also be out of sequence. Treat these rows as suspect until their dates are checked against source records.

---

### 9. Products without a category — 37 products (MEDIUM)

**What:** 37 products either have `category_id IS NULL` or point to a category that does not exist.

**How to verify:**
```sql
SELECT count(*) FROM products
WHERE category_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM categories c WHERE c.category_id = products.category_id);
```

**Cost to Nana:** Low-stock visibility rolled up through the category tree will miss these 37 products entirely. The rollup is incomplete.

---

### 10. Category tree has an orphan and a disconnected cycle — 3 unreachable categories (MEDIUM)

**What:** Three categories cannot be reached from a root: "Seasonal Promotions" (id 9001) points to "Promotions" (9002), and "Promotions" points back to 9001, forming a cycle. "Clearance" (9003) points to missing parent 8999. The missing-parent finding is part of these three unreachable categories, not an additional fourth category.

**How to verify:**
```sql
WITH RECURSIVE reached(category_id) AS (
    SELECT category_id FROM categories WHERE parent_id IS NULL
    UNION
    SELECT c.category_id
    FROM categories c
    JOIN reached r ON c.parent_id = r.category_id
)
SELECT c.category_id, c.category_name, c.parent_id
FROM categories c
WHERE NOT EXISTS (
    SELECT 1 FROM reached r WHERE r.category_id = c.category_id
)
ORDER BY c.category_id;
```

**Cost to Nana:** A rollup that starts from roots silently misses all three categories. A traversal started inside the 9001/9002 loop can repeat forever if it does not track visited categories.

---

### 11. Duplicate customer emails — 533 groups after normalization (MEDIUM)

**What:** Grouping the stored email strings exactly finds 299 duplicate groups. When trimming spaces and ignoring capitalization, 533 non-empty normalized email groups have more than one customer row. The schema has no unique constraint on email.

**How to verify:**
```sql
SELECT count(*) FROM (
    SELECT lower(trim(email))
    FROM customers
    WHERE coalesce(trim(email), '') <> ''
    GROUP BY 1
    HAVING count(*) > 1
) normalized;
```

**Cost to Nana:** Customer dedup is unreliable. One real customer may appear as multiple rows, inflating customer counts and splitting their spend across fake identities. Top-100 ranking and per-customer totals are distorted.

---

## Problems That Looked Wrong But Are Not

| Check | Result | Note |
|-------|--------|------|
| NULL primary keys | 0 | All PKs populated |
| Duplicate primary keys | 0 | No duplicate PKs |
| Self-referencing categories | 0 | No category is its own parent |
| Duplicate category names | 0 | All category names unique (case-insensitive) |
| Empty category names | 0 | All categories have names |
| Zero/negative order quantities | 0 | All order_items have positive quantity |
| Extreme negative inventory changes (< -1000) | 0 | No extreme outliers |
| Orders without items | 0 | Every order has at least one line item |
| Order items referencing missing products | 0 | Every receipt line's product exists |
| Products in orphan Clearance category | 0 | Category 9003 has no products assigned |
| Orders before matched customer's registration | 0 | No cases found in this extract; guest checkout policy still matters |
| Zero-stock products with historical order items | 577 products | This only links today's stock value (zero) to historical sales. It does not show stock was zero when an order was placed, so it is not evidence of overselling. |
| Inventory movement signs | 0 obvious sale/restock sign conflicts | All sales are negative, restocks and returns positive, damage negative; corrections include both signs and stock-take entries are zero |
| Product catalogue prices | 0 NULL or non-positive | All product prices are positive and present |
| Zero-priced receipt lines | 152 lines | Could be free gifts; verify before treating as bad data |

---

## Summary Table

| Rank | Problem | Affected | Danger | Nana's Cost |
|------|---------|----------|--------|-------------|
| 1 | Negative product stock | 14 products | Critical | Confirmed oversell evidence; stock is below zero |
| 2 | Stock/log net-change mismatch (baseline unverified) | 144 products | High, provisional | Stock accuracy cannot be confirmed without the opening-balance rule |
| 3 | Free-text order statuses | 15 spellings across 159,384 orders | High | Spend and customer rankings may omit or include the wrong orders |
| 4 | Order total and receipt-line differences | 2,426 orders; 148 NULL-priced lines | High | Neither stored total nor line sum is proven authoritative |
| 5 | order_items missing order | 692 line items | High | Revenue understated, order counts wrong |
| 6 | Orders missing customer | 210 orders | High | Per-customer totals incomplete |
| 7 | inventory_log missing product | 120 entries | High | Broken audit trail for auditor |
| 8 | Dates after August 2026 data end point | 24 orders; 40 inventory entries | Medium | Monthly report and movement timeline may be misleading |
| 9 | Products without category | 37 products | Medium | Low-stock rollup incomplete |
| 10 | Categories unreachable from roots | 3 categories | Medium | Cycle and missing parent make the category rollup incomplete |
| 11 | Duplicate customer emails after normalization | 533 groups | Medium | Customer dedup unreliable, spend split |

---

## What This Means for the Solution

| Area | What the Data Tells Us |
|------|------------------------|
| **Overselling fix** | Must prevent *any* sale when stock ≤ 0. The current app doesn't check atomically — two concurrent orders both see 1 unit, both succeed. |
| **Report fix** | Must decide which statuses count as spend, reconcile `orders.total_amount` with receipt lines (including missing prices and possible fees/discounts), exclude or flag dates after the August 2026 data end point, handle duplicate customers, and run in seconds. |
| **Category rollup** | Must tolerate missing parents, cycles, and orphans, track visited categories, and not hard-code depth. |
| **Audit trail** | `place_order` records new sales with their order and stock change. The current solution does not yet force direct stock updates, restocks, and corrections through a logged operation. A trusted opening-stock baseline is also needed before historical stock/log differences can be verified. |
| **Schema changes** | Need foreign keys, check constraints, and indexes. Document every change so Nana's team can live with it. |

---

## Audit Query Files (for verification)

| File | Purpose |
|------|---------|
| `sql/01_audit/01_nulls.sql` | NULL checks on PKs and critical columns |
| `sql/01_audit/02_duplicates.sql` | Duplicate primary keys |
| `sql/01_audit/03_stock_issues.sql` | Negative stock, stock/log comparison, movement reasons/signs, and historical sales for products currently at zero stock |
| `sql/01_audit/04_referential_integrity.sql` | Orphaned rows, missing parent references |
| `sql/01_audit/05_category_issues.sql` | Category tree depth, cycles, missing parents, and unreachable category names |
| `sql/01_audit/06_customer_issues.sql` | Exact and normalized duplicate customer emails |
| `sql/01_audit/07_financial_issues.sql` | Order/line total differences and missing or non-positive prices |
| `sql/01_audit/08_data_quality.sql` | Exact status counts and amounts, records after the August 2026 cutoff, and orders before registration |

Run any file with:
```bash
docker exec kloudkart-db psql -U postgres -d kloudkart -f /sql/01_audit/XX_filename.sql
```

---

## Next Steps

These findings feed into:

- **`02_key_decisions.md`** — how we fix overselling (row-level locking in the order procedure, not triggers alone), how we make the report fast, and each assumption we made.
- **`03_memo_to_nana.md`** — one-page business summary.
- **`sql/02_schema_changes/`** — sequences, foreign keys, indexes, and constraints. A controlled, logged path for restocks and corrections remains a production follow-up; it is not implemented by these schema changes.