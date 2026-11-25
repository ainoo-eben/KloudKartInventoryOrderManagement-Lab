-- Audit: Referential integrity / orphaned rows
-- Source: checks #6, #7, #8, #9, #10

SELECT 'orders without items' AS check_name, count(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.order_id)
UNION ALL SELECT 'order_items with missing order', count(*) FROM order_items oi WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = oi.order_id)
UNION ALL SELECT 'order_items with missing product', count(*) FROM order_items oi WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = oi.product_id)
UNION ALL SELECT 'orders with missing customer', count(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)
UNION ALL SELECT 'inventory_log with missing product', count(*) FROM inventory_log il WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = il.product_id);
