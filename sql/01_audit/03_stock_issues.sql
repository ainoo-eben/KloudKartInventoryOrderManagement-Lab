-- Audit: Stock quantity issues
-- Source: checks #3, #4, #5, #16

SELECT 'negative product stock' AS check_name, count(*) FROM products WHERE stock_quantity < 0
UNION ALL SELECT 'zero/negative order_items quantity', count(*) FROM order_items WHERE quantity <= 0
UNION ALL SELECT 'inventory_log extreme negative change_qty (< -1000)', count(*) FROM inventory_log WHERE change_qty < -1000
UNION ALL SELECT 'zero-stock products with historical order items (not proof of overselling)', count(DISTINCT oi.product_id)
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
WHERE p.stock_quantity = 0;

-- This comparison is only a true reconciliation if the log includes each
-- product's opening stock or otherwise starts from a known zero balance.
SELECT count(*) AS products_without_inventory_log
FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM inventory_log il WHERE il.product_id = p.product_id
);

SELECT count(*) AS products_not_matching_logged_net_change
FROM (
    SELECT p.product_id
    FROM products p
    LEFT JOIN inventory_log il ON il.product_id = p.product_id
    GROUP BY p.product_id, p.stock_quantity
    HAVING p.stock_quantity <> coalesce(sum(il.change_qty), 0)
) mismatches;

SELECT '[' || coalesce(reason, '<NULL>') || ']' AS reason_exactly,
       count(*) AS entries,
       min(change_qty) AS min_change,
       max(change_qty) AS max_change,
       count(*) FILTER (WHERE change_qty > 0) AS positive_entries,
       count(*) FILTER (WHERE change_qty = 0) AS zero_entries,
       count(*) FILTER (WHERE change_qty < 0) AS negative_entries
FROM inventory_log
GROUP BY reason
ORDER BY entries DESC;
