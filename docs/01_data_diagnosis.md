# 01 Data Diagnosis

Kloud Kart Ltd. data audit results. Every problem found, how it was detected, what it costs Nana if uncorrected, ranked by danger.

## Method

Ran the audit queries in `sql/01_audit/*.sql` against a fresh load of `data/schema.sql` + `data/load.sql`. Each check queries the loaded tables directly and reports a count of offending rows.

## Findings, ranked by danger

### 1. Zero-stock products sold — 577 sales (CRITICAL)

**What:** 577 distinct products with `stock_quantity = 0` still appear in `order_items`, meaning customers paid for stock that did not exist.

**How detected:** Join `order_items` to `products` where `products.stock_quantity = 0`, count distinct products.

**Cost if uncorrected:** Direct overselling. Every one of these is a refund, an apology, and a review Nana can't undo. Stock counts no longer match reality. This is the exact problem Nana loses sleep over.

### 2. Products with negative stock — 14 products (CRITICAL)

**What:** 14 products have `stock_quantity < 0` in the `products` table.

**How detected:** `SELECT count(*) FROM products WHERE stock_quantity < 0` returned 14.

**Cost if uncorrected:** The database believes Kloud Kart owes inventory it doesn't have. These products are already oversold beyond zero. Any new order for them will deepen the hole.

### 3. Orders with mismatched total_amount — 2,426 orders (HIGH)

**What:** 2,426 orders have an `orders.total_amount` that does not equal the sum of `order_items.quantity * order_items.unit_price` for that order.

**How detected:** Joined `orders` to aggregated `order_items` per order and compared `o.total_amount` to the calculated sum using `IS DISTINCT FROM`.

**Cost if uncorrected:** Adwoa's customer-spending report is built on `total_amount`. If ~1.5% of order totals are wrong, every weekly report is silently inaccurate. Nana has been deciding without this report because he doesn't trust it — this is why.

### 4. order_items referencing missing orders — 692 line items (HIGH)

**What:** 692 rows in `order_items` point to an `order_id` that does not exist in `orders`.

**How detected:** `NOT EXISTS` anti-join from `order_items` to `orders` on `order_id`.

**Cost if uncorrected:** These sales are invisible to the orders table. Revenue is understated, customer order counts are wrong, and the audit trail has gaps.

### 5. Orders referencing missing customers — 210 orders (HIGH)

**What:** 210 orders point to a `customer_id` that does not exist in `customers`.

**How detected:** `NOT EXISTS` anti-join from `orders` to `customers` on `customer_id`.

**Cost if uncorrected:** Adwoa cannot attribute spend to a real customer. Top-100 customer ranking and per-customer totals are incomplete. These customers effectively don't exist in the report.

### 6. inventory_log referencing missing products — 120 entries (HIGH)

**What:** 120 rows in `inventory_log` point to a `product_id` that does not exist in `products`.

**How detected:** `NOT EXISTS` anti-join from `inventory_log` to `products` on `product_id`.

**Cost if uncorrected:** The audit trail is broken. An auditor walking through stock movements for these products hits dead ends. This violates Nana's requirement for a complete trail of every stock movement.

### 7. Products without a category — 37 products (MEDIUM)

**What:** 37 products either have `category_id IS NULL` or point to a category that does not exist.

**How detected:** `NOT EXISTS` anti-join from `products` to `categories` on `category_id`, plus NULL check.

**Cost if uncorrected:** Low-stock visibility rolled up through the category tree will miss these 37 products entirely. The rollup is incomplete.

### 8. Categories not reached by recursive traversal — 3 categories (MEDIUM)

**What:** 3 categories are not reachable from any root category via the parent chain (possible cycle or disconnected branch).

**How detected:** Recursive CTE starting from root categories (parent_id IS NULL) and walking down; counted categories not visited.

**Cost if uncorrected:** A recursive rollup that starts at roots will silently skip these branches. Low-stock visibility is incomplete in those areas.

### 9. Category with missing parent — 1 category (MEDIUM)

**What:** 1 category has a `parent_id` that points to a non-existent category.

**How detected:** `NOT EXISTS` anti-join from `categories` to itself on `parent_id`.

**Cost if uncorrected:** The category tree has a dangling branch. Recursive traversal from roots stops at this category's children.

### 10. Duplicate customer emails — 299 duplicate email groups (MEDIUM)

**What:** 299 email addresses appear on more than one customer row (emails are not unique, per schema).

**How detected:** Group by email where count > 1, excluding NULL emails.

**Cost if uncorrected:** Customer dedup is unreliable. One real customer may appear as multiple rows, inflating customer counts and splitting their spend across fake identities. Top-100 ranking and per-customer totals are distorted.

### 11. Future order dates — 16 orders (LOW)

**What:** 16 orders have `order_date` in the future (after `now()`).

**How detected:** `SELECT count(*) FROM orders WHERE order_date > now()`.

**Cost if uncorrected:** Date-based filtering (trailing 12 months) may include orders that haven't happened yet, slightly inflating recent spend.

### 12. Future inventory_log dates — 33 entries (LOW)

**What:** 33 inventory_log entries have `created_at` in the future.

**How detected:** `SELECT count(*) FROM inventory_log WHERE created_at > now()`.

**Cost if uncorrected:** Audit trail timestamps are suspect. An auditor checking the sequence of stock movements will see out-of-order dates.

### 13. Distinct order statuses — 15 values (LOW)

**What:** The `status` column is free text with 15 distinct values, no check constraint.

**How detected:** `SELECT count(DISTINCT status) FROM orders`.

**Cost if uncorrected:** Report filtering by status (e.g., "completed" vs "cancelled") is fragile. Misspelled variants silently exclude orders.

## Problems that looked wrong but are not

None flagged in this run required a "not a problem" callout. Every non-zero count above represents a genuine data integrity risk.

## Summary table

| Rank | Problem | Rows affected | Danger | Nana's cost |
|------|---------|---------------|--------|-------------|
| 1 | Zero-stock products sold | 577 products | Critical | Refunds, apologies, lost reviews |
| 2 | Negative product stock | 14 products | Critical | Stock counts below zero, deepening oversell hole |
| 3 | Order total_amount mismatch | 2,426 orders | High | Weekly spend report silently wrong (~1.5%) |
| 4 | order_items missing order | 692 line items | High | Revenue understated, order counts wrong |
| 5 | Orders missing customer | 210 orders | High | Per-customer totals incomplete |
| 6 | inventory_log missing product | 120 entries | High | Broken audit trail for auditor |
| 7 | Products without category | 37 products | Medium | Low-stock rollup incomplete |
| 8 | Categories unreachable by recursion | 3 categories | Medium | Category tree rollup skips branches |
| 9 | Category missing parent | 1 category | Medium | Dangling branch in tree |
| 10 | Duplicate customer emails | 299 groups | Medium | Customer dedup unreliable, spend split |
| 11 | Future order dates | 16 orders | Low | Trailing 12-month window polluted |
| 12 | Future inventory_log dates | 33 entries | Low | Audit timestamps suspect |
| 13 | Free-text order statuses | 15 values | Low | Status filtering fragile |

## Next steps

These findings feed into:

- **`02_key_decisions.md`** — how we fix overselling (row-level locking in the order procedure, not triggers alone), how we make the report fast, and each assumption we made.
- **`03_memo_to_nana.md`** — one-page business summary.
- Schema changes (foreign keys, indexes, constraints) and an audit trigger so future stock movements can't happen without a log row.

## Audit query files

The individual diagnostic queries live in `sql/01_audit/`:

- `sql/01_audit/01_nulls.sql` — NULL checks
- `sql/01_audit/02_duplicates.sql` — Duplicate PKs
- `sql/01_audit/03_stock_issues.sql` — Stock and overselling evidence
- `sql/01_audit/04_referential_integrity.sql` — Orphaned rows
- `sql/01_audit/05_category_issues.sql` — Category tree problems
- `sql/01_audit/06_customer_issues.sql` — Duplicate emails
- `sql/01_audit/07_financial_issues.sql` — Total amount mismatches
- `sql/01_audit/08_data_quality.sql` — Statuses and dates

See `sql/01_audit/README.md` for how to run them.
