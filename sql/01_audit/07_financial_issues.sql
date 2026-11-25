-- Audit: Financial data quality and receipt-line prices

SELECT 'orders total_amount mismatch' AS check_name, count(*)
FROM orders o
JOIN (
    SELECT order_id, sum(quantity * unit_price) AS calc_total
    FROM order_items
    GROUP BY order_id
) i ON i.order_id = o.order_id
WHERE o.total_amount IS DISTINCT FROM i.calc_total;

SELECT 'product price checks' AS check_name,
       count(*) FILTER (WHERE price IS NULL) AS null_prices,
       count(*) FILTER (WHERE price <= 0) AS zero_or_negative_prices
FROM products;

SELECT 'order-item unit_price checks' AS check_name,
       count(*) FILTER (WHERE unit_price IS NULL) AS null_prices,
       count(*) FILTER (WHERE unit_price <= 0) AS zero_or_negative_prices
FROM order_items;

-- A difference alone does not establish which amount is correct. Check
-- whether there is a repeated fixed fee/discount before choosing a report basis.
SELECT o.total_amount - i.calc_total AS difference, count(*) AS orders
FROM orders o
JOIN (
    SELECT order_id, sum(quantity * unit_price) AS calc_total
    FROM order_items
    GROUP BY order_id
) i ON i.order_id = o.order_id
WHERE o.total_amount IS DISTINCT FROM i.calc_total
GROUP BY 1
ORDER BY 2 DESC
LIMIT 15;
