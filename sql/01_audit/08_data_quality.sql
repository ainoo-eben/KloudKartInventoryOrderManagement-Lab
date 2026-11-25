-- Audit: General data quality (statuses, dates)
-- The extract's latest credible month is August 2026. Treat later rows as suspect.

SELECT quote_literal(status) || ' [length=' || length(status) || ']' AS exact_status,
       count(*) AS orders,
       sum(total_amount) AS recorded_order_total
FROM orders
GROUP BY status
ORDER BY orders DESC, exact_status;

SELECT 'orders dated on/after 2026-09-01' AS check_name, count(*) FROM orders
WHERE order_date >= DATE '2026-09-01'
UNION ALL
SELECT 'inventory entries dated on/after 2026-09-01', count(*) FROM inventory_log
WHERE created_at >= DATE '2026-09-01'
UNION ALL
SELECT 'orders in August 2026 (cutoff baseline)', count(*) FROM orders
WHERE order_date >= DATE '2026-08-01' AND order_date < DATE '2026-09-01'
UNION ALL
SELECT 'orders in September 2026 (post-cutoff example)', count(*) FROM orders
WHERE order_date >= DATE '2026-09-01' AND order_date < DATE '2026-10-01';

SELECT count(*) AS orders_before_customer_registration
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_date < c.registered_at;
