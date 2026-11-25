-- Audit: General data quality (statuses, dates)
-- Source: checks #15, #17, #18

SELECT 'distinct order statuses' AS check_name, count(*) FROM (SELECT DISTINCT status FROM orders) t
UNION ALL SELECT 'future order dates', count(*) FROM orders WHERE order_date > now()
UNION ALL SELECT 'future inventory_log dates', count(*) FROM inventory_log WHERE created_at > now();
