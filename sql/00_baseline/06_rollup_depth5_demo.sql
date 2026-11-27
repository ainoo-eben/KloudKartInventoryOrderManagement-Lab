-- Demonstrates why the rollup must not hard-code depth.
-- Marketing adds a 5th-level subcategory and moves one low-stock product into
-- it. The fixed-depth rollup silently stops counting that product at the top
-- of the tree; the recursive low_stock_rollup() keeps counting it.
-- Everything is rolled back.
--
-- Requires low_stock_rollup() installed. Run after 05_naive_rollup_fixed_depth.sql
-- in the same psql session (the naive view is session-temporary).

BEGIN;

-- Pick a depth-4 category, add a child under it, and move one low-stock
-- product from anywhere in the catalogue into the new 5th-level category.
CREATE TEMP TABLE demo_pick ON COMMIT DROP AS
SELECT
    (SELECT category_id FROM low_stock_rollup(10)
      WHERE is_reachable AND depth = 4 ORDER BY category_id LIMIT 1) AS level4_id,
    (SELECT max(category_id) + 1 FROM categories)                    AS new_level5_id,
    (SELECT product_id FROM products
      WHERE stock_quantity BETWEEN 0 AND 10
        AND category_id IN (SELECT category_id FROM low_stock_rollup(10) WHERE is_reachable)
      ORDER BY product_id LIMIT 1)                                   AS moved_product_id;

CREATE TEMP TABLE before_move ON COMMIT DROP AS
SELECT
    (SELECT sum(low_stock_product_count) FROM low_stock_rollup(10) WHERE depth = 1) AS recursive_roots_total,
    (SELECT sum(n.low_stock_product_count)
       FROM pg_temp.naive_low_stock_rollup n
       JOIN categories c ON c.category_id = n.category_id
      WHERE c.parent_id IS NULL)                                                   AS naive_roots_total;

INSERT INTO categories (category_id, category_name, parent_id)
SELECT new_level5_id, 'Demo Level-5 Subcategory', level4_id FROM demo_pick;

UPDATE products
SET category_id = (SELECT new_level5_id FROM demo_pick)
WHERE product_id = (SELECT moved_product_id FROM demo_pick);

SELECT
    'after adding a 5th level' AS scenario,
    b.recursive_roots_total AS recursive_before,
    (SELECT sum(low_stock_product_count) FROM low_stock_rollup(10) WHERE depth = 1) AS recursive_after,
    b.naive_roots_total AS fixed_depth_before,
    (SELECT sum(n.low_stock_product_count)
       FROM pg_temp.naive_low_stock_rollup n
       JOIN categories c ON c.category_id = n.category_id
      WHERE c.parent_id IS NULL) AS fixed_depth_after,
    (SELECT max(depth) FROM low_stock_rollup(10)) AS max_depth_now
FROM before_move b;

ROLLBACK;
