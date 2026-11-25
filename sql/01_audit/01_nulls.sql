-- Audit: NULL checks on primary keys and critical columns
-- Source: check #1

SELECT 'categories NULL category_id' AS check_name, count(*) FROM categories WHERE category_id IS NULL
UNION ALL SELECT 'categories NULL category_name', count(*) FROM categories WHERE category_name IS NULL
UNION ALL SELECT 'products NULL product_id', count(*) FROM products WHERE product_id IS NULL
UNION ALL SELECT 'products NULL product_name', count(*) FROM products WHERE product_name IS NULL
UNION ALL SELECT 'products NULL stock_quantity', count(*) FROM products WHERE stock_quantity IS NULL
UNION ALL SELECT 'customers NULL customer_id', count(*) FROM customers WHERE customer_id IS NULL
UNION ALL SELECT 'customers NULL full_name', count(*) FROM customers WHERE full_name IS NULL
UNION ALL SELECT 'orders NULL order_id', count(*) FROM orders WHERE order_id IS NULL
UNION ALL SELECT 'orders NULL customer_id', count(*) FROM orders WHERE customer_id IS NULL
UNION ALL SELECT 'orders NULL order_date', count(*) FROM orders WHERE order_date IS NULL
UNION ALL SELECT 'order_items NULL order_item_id', count(*) FROM order_items WHERE order_item_id IS NULL
UNION ALL SELECT 'order_items NULL order_id', count(*) FROM order_items WHERE order_id IS NULL
UNION ALL SELECT 'order_items NULL product_id', count(*) FROM order_items WHERE product_id IS NULL
UNION ALL SELECT 'order_items NULL quantity', count(*) FROM order_items WHERE quantity IS NULL
UNION ALL SELECT 'inventory_log NULL log_id', count(*) FROM inventory_log WHERE log_id IS NULL
UNION ALL SELECT 'inventory_log NULL product_id', count(*) FROM inventory_log WHERE product_id IS NULL
UNION ALL SELECT 'inventory_log NULL change_qty', count(*) FROM inventory_log WHERE change_qty IS NULL
UNION ALL SELECT 'inventory_log NULL created_at', count(*) FROM inventory_log WHERE created_at IS NULL
ORDER BY 1;
