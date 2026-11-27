-- Naive "before" low-stock rollup: hard-codes four levels of self-joins.
-- This is the approach the brief forbids ("don't hard-code how deep the
-- category tree goes"). It is kept only as a comparison for
-- scripts/benchmark.ps1 and 06_rollup_depth5_demo.sql.
--
-- It happens to be correct on today's 4-level tree, silently drops products
-- once a 5th level exists, and never sees the 9001/9002 cycle or the
-- orphan Clearance category as a problem.

CREATE OR REPLACE VIEW pg_temp.naive_low_stock_rollup AS
WITH ancestor_pairs AS (
    SELECT c1.category_id AS ancestor_id, c1.category_id AS descendant_id
    FROM categories c1
    UNION ALL
    SELECT c1.category_id, c2.category_id
    FROM categories c1
    JOIN categories c2 ON c2.parent_id = c1.category_id
    UNION ALL
    SELECT c1.category_id, c3.category_id
    FROM categories c1
    JOIN categories c2 ON c2.parent_id = c1.category_id
    JOIN categories c3 ON c3.parent_id = c2.category_id
    UNION ALL
    SELECT c1.category_id, c4.category_id
    FROM categories c1
    JOIN categories c2 ON c2.parent_id = c1.category_id
    JOIN categories c3 ON c3.parent_id = c2.category_id
    JOIN categories c4 ON c4.parent_id = c3.category_id
)
SELECT
    a.category_id,
    a.category_name,
    count(p.product_id)::bigint AS low_stock_product_count,
    coalesce(sum(p.stock_quantity), 0)::bigint AS low_stock_units
FROM categories a
LEFT JOIN ancestor_pairs ap ON ap.ancestor_id = a.category_id
-- The low-stock filter is in the ON clause (not WHERE) so categories with no
-- low-stock products still appear with 0. Both output columns therefore count
-- LOW-STOCK products only (stock <= 10), not all products in the category,
-- matching low_stock_rollup(10).
LEFT JOIN products p
       ON p.category_id = ap.descendant_id
      AND p.stock_quantity <= 10
GROUP BY a.category_id, a.category_name;
