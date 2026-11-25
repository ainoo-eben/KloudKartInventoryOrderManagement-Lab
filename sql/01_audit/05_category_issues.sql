-- Audit: Category tree issues
-- Source: checks #11, #12, #19, #20

SELECT 'categories with missing parent' AS check_name, count(*) FROM categories c WHERE c.parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categories p WHERE p.category_id = c.parent_id)
UNION ALL SELECT 'self-referencing categories', count(*) FROM categories c WHERE c.category_id = c.parent_id
UNION ALL SELECT 'products without category', count(*) FROM products WHERE category_id IS NULL OR NOT EXISTS (SELECT 1 FROM categories c WHERE c.category_id = products.category_id);

WITH RECURSIVE cat_depth AS (
    SELECT category_id, category_name, parent_id, 1 AS depth
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_id, cd.depth + 1
    FROM categories c
    JOIN cat_depth cd ON cd.category_id = c.parent_id
)
SELECT 'max category depth' AS check_name, max(depth) FROM cat_depth
UNION ALL SELECT 'categories not reached by recursion (possible cycle)', count(*) FROM categories c
WHERE NOT EXISTS (SELECT 1 FROM cat_depth cd WHERE cd.category_id = c.category_id);
