-- Audit: Financial data quality
-- Source: check #14

SELECT 'orders total_amount mismatch' AS check_name, count(*)
FROM orders o
JOIN (
    SELECT order_id, sum(quantity * unit_price) AS calc_total
    FROM order_items
    GROUP BY order_id
) i ON i.order_id = o.order_id
WHERE o.total_amount IS DISTINCT FROM i.calc_total;
