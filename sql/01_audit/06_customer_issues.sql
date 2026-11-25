-- Audit: Customer data quality
-- Source: check #13

SELECT 'duplicate emails' AS check_name, count(*) FROM (SELECT email FROM customers WHERE email IS NOT NULL GROUP BY email HAVING count(*) > 1) t;
