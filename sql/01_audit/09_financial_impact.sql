-- What each data problem puts at stake, in Ghana cedis (GHS).
-- Read-only. Amounts are RECORDED values (orders.total_amount, or
-- quantity * unit_price for receipt lines, or stock units * catalogue price),
-- not verified payments. They size the risk; they are not a loss figure.
-- Feeds the "GHS at stake" column in docs/01_data_diagnosis.md.

WITH status_norm AS (
    SELECT o.*, lower(btrim(o.status)) AS s
    FROM orders o
),
line_totals AS (
    SELECT order_id, sum(quantity * unit_price) AS line_total
    FROM order_items
    GROUP BY order_id
),
log_net AS (
    SELECT product_id, sum(change_qty) AS net
    FROM inventory_log
    GROUP BY product_id
),
dup_customers AS (
    SELECT c.customer_id
    FROM customers c
    WHERE coalesce(btrim(c.email), '') <> ''
      AND lower(btrim(c.email)) IN (
          SELECT lower(btrim(email)) FROM customers
          WHERE coalesce(btrim(email), '') <> ''
          GROUP BY 1 HAVING count(*) > 1
      )
)
SELECT * FROM (
    SELECT 1 AS rank, 'Negative stock: value of units sold below zero' AS problem,
           count(*)::bigint AS affected,
           sum(-p.stock_quantity * p.price) AS ghs_at_stake,
           'units below zero x catalogue price' AS basis
    FROM products p WHERE p.stock_quantity < 0

    UNION ALL
    SELECT 2, 'Stock vs log mismatch: value of unexplained units',
           count(*), sum(abs(p.stock_quantity - coalesce(l.net, 0)) * p.price),
           '|stock - logged net| x catalogue price (unverified baseline)'
    FROM products p LEFT JOIN log_net l ON l.product_id = p.product_id
    WHERE p.stock_quantity IS DISTINCT FROM coalesce(l.net, 0)

    UNION ALL
    SELECT 3, 'Status: cancelled/refunded money an all-status report counts as spend',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM status_norm WHERE s IN ('cancelled', 'canceled', 'refunded')

    UNION ALL
    SELECT 3, 'Status: pending money an all-status report counts as spend',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM status_norm WHERE s = 'pending'

    UNION ALL
    SELECT 3, 'Status: real spend missed by an exact status = ''completed'' filter',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM status_norm
    WHERE s IN ('completed', 'complete', 'shipped') AND status <> 'completed'

    UNION ALL
    SELECT 4, 'Order total vs receipt lines: gross difference',
           count(*), sum(abs(o.total_amount - lt.line_total)),
           'sum of |total_amount - line total|, orders with calculable lines'
    FROM orders o JOIN line_totals lt ON lt.order_id = o.order_id
    WHERE lt.line_total IS NOT NULL AND o.total_amount IS DISTINCT FROM lt.line_total

    UNION ALL
    SELECT 4, 'Order total vs receipt lines: net difference (total - lines)',
           count(*), sum(o.total_amount - lt.line_total),
           'signed; shows whether differences cancel out'
    FROM orders o JOIN line_totals lt ON lt.order_id = o.order_id
    WHERE lt.line_total IS NOT NULL AND o.total_amount IS DISTINCT FROM lt.line_total

    UNION ALL
    SELECT 5, 'Receipt lines with no order',
           count(*), sum(oi.quantity * oi.unit_price), 'quantity x unit_price'
    FROM order_items oi
    WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = oi.order_id)

    UNION ALL
    SELECT 6, 'Orders with no customer (all statuses)',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM status_norm o
    WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)

    UNION ALL
    SELECT 6, 'Orders with no customer (spend statuses only, dropped from report)',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM status_norm o
    WHERE s IN ('completed', 'complete', 'shipped')
      AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)

    UNION ALL
    SELECT 7, 'Inventory movements for unknown products',
           count(*), NULL::numeric, 'no product, so no price: '
             || coalesce(sum(abs(change_qty)), 0) || ' units moved'
    FROM inventory_log il
    WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = il.product_id)

    UNION ALL
    SELECT 8, 'Orders dated after 2026-08-31 cutoff',
           count(*), sum(total_amount), 'orders.total_amount'
    FROM orders WHERE order_date >= TIMESTAMP '2026-09-01'

    UNION ALL
    SELECT 9, 'Products with no/missing category: stock value hidden from rollup',
           count(*), sum(p.stock_quantity * p.price), 'stock x catalogue price'
    FROM products p
    WHERE p.category_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM categories c WHERE c.category_id = p.category_id)

    UNION ALL
    SELECT 10, 'Products in categories unreachable from a root: stock value',
           count(*), coalesce(sum(p.stock_quantity * p.price), 0),
           'stock x catalogue price; categories outside the root-based tree'
    FROM products p
    WHERE p.category_id IN (
        SELECT c.category_id FROM categories c
        WHERE c.category_id NOT IN (
            WITH RECURSIVE reached(category_id) AS (
                SELECT category_id FROM categories WHERE parent_id IS NULL
                UNION
                SELECT c2.category_id FROM categories c2
                JOIN reached r ON c2.parent_id = r.category_id
            )
            SELECT category_id FROM reached
        )
    )

    UNION ALL
    SELECT 11, 'Customers in duplicate-email groups: spend split across rows',
           count(DISTINCT d.customer_id), sum(o.total_amount),
           'spend-status orders of customers sharing a normalized email'
    FROM dup_customers d
    LEFT JOIN status_norm o
           ON o.customer_id = d.customer_id
          AND o.s IN ('completed', 'complete', 'shipped')
) impact
ORDER BY rank, problem;
