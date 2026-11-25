-- Audit: Duplicate primary key checks
-- Source: check #2

SELECT 'dup categories' AS check_name, count(*) FROM (SELECT category_id FROM categories GROUP BY category_id HAVING count(*) > 1) t
UNION ALL SELECT 'dup products', count(*) FROM (SELECT product_id FROM products GROUP BY product_id HAVING count(*) > 1) t
UNION ALL SELECT 'dup customers', count(*) FROM (SELECT customer_id FROM customers GROUP BY customer_id HAVING count(*) > 1) t
UNION ALL SELECT 'dup orders', count(*) FROM (SELECT order_id FROM orders GROUP BY order_id HAVING count(*) > 1) t
UNION ALL SELECT 'dup order_items', count(*) FROM (SELECT order_item_id FROM order_items GROUP BY order_item_id HAVING count(*) > 1) t
UNION ALL SELECT 'dup inventory_log', count(*) FROM (SELECT log_id FROM inventory_log GROUP BY log_id HAVING count(*) > 1) t
ORDER BY 1;
