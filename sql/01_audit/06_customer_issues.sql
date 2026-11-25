-- Audit: Customer data quality
-- Source: check #13

SELECT 'duplicate emails' AS check_name, count(*) FROM (SELECT email FROM customers WHERE email IS NOT NULL GROUP BY email HAVING count(*) > 1) t;

SELECT 'duplicate email groups after lower/trim normalization' AS check_name,
       count(*)
FROM (
    SELECT lower(trim(email))
    FROM customers
    WHERE coalesce(trim(email), '') <> ''
    GROUP BY 1
    HAVING count(*) > 1
) normalized;
