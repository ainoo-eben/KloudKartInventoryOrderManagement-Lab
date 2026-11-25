-- Audit: Stock quantity issues
-- Source: checks #3, #4, #5, #16

SELECT 'negative product stock' AS check_name, count(*) FROM products WHERE stock_quantity < 0
UNION ALL SELECT 'zero/negative order_items quantity', count(*) FROM order_items WHERE quantity <= 0
UNION ALL SELECT 'inventory_log extreme negative change_qty (< -1000)', count(*) FROM inventory_log WHERE change_qty < -1000
UNION ALL SELECT 'zero-stock products sold', count(DISTINCT oi.product_id)
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
WHERE p.stock_quantity = 0;
