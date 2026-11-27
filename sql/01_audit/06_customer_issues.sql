-- Audit: Customer data quality
-- Source: check #13
--
-- The two counts below are NOT comparable. The first is an exact,
-- case-sensitive match ('Ama@x.com' and 'ama@x.com ' are different). The
-- second lower-cases and trims first, so it finds every group the first one
-- finds plus the case/space variants. Use the second for impact figures.

SELECT 'duplicate email groups (exact, case-sensitive match)' AS check_name,
       count(*)
FROM (
    SELECT email
    FROM customers
    WHERE email IS NOT NULL
    GROUP BY email
    HAVING count(*) > 1
) AS exact_duplicate_emails;

SELECT 'duplicate email groups after lower/trim normalization' AS check_name,
       count(*)
FROM (
    SELECT lower(trim(email))
    FROM customers
    WHERE coalesce(trim(email), '') <> ''
    GROUP BY 1
    HAVING count(*) > 1
) AS normalized_duplicate_emails;
