-- Low-stock rollup through the category tree.
-- The default threshold of 10 units is a documented, adjustable assumption.
-- Unreachable categories report direct-category counts only; their ancestors
-- cannot be trusted until the existing cycle/orphan links are resolved.

CREATE OR REPLACE FUNCTION public.low_stock_rollup(
    p_threshold integer DEFAULT 10
)
RETURNS TABLE (
    category_id integer,
    category_name text,
    parent_id integer,
    category_path text,
    depth integer,
    is_reachable boolean,
    low_stock_product_count bigint,
    low_stock_units bigint,
    rollup_scope text
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
    IF p_threshold IS NULL OR p_threshold < 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'p_threshold must be zero or greater';
    END IF;

    RETURN QUERY
    WITH RECURSIVE category_tree AS (
        SELECT
            c.category_id,
            c.parent_id,
            c.category_name,
            1 AS depth,
            ARRAY[c.category_id] AS id_path,
            ARRAY[coalesce(c.category_name, '(unnamed)')]::text[] AS name_path
        FROM public.categories AS c
        WHERE c.parent_id IS NULL

        UNION ALL

        SELECT
            c.category_id,
            c.parent_id,
            c.category_name,
            parent.depth + 1,
            parent.id_path || c.category_id,
            parent.name_path || coalesce(c.category_name, '(unnamed)')
        FROM public.categories AS c
        JOIN category_tree AS parent
          ON c.parent_id = parent.category_id
        WHERE NOT c.category_id = ANY(parent.id_path)
    ),
    direct_low_stock AS (
        SELECT
            p.category_id,
            count(*)::bigint AS product_count,
            sum(p.stock_quantity)::bigint AS stock_units
        FROM public.products AS p
        WHERE p.stock_quantity <= p_threshold
        GROUP BY p.category_id
    ),
    reachable_rollup AS (
        SELECT
            ancestors.category_id,
            sum(direct.product_count)::bigint AS product_count,
            sum(direct.stock_units)::bigint AS stock_units
        FROM category_tree AS descendants
        CROSS JOIN LATERAL unnest(descendants.id_path)
            AS ancestors(category_id)
        JOIN direct_low_stock AS direct
          ON direct.category_id = descendants.category_id
        GROUP BY ancestors.category_id
    ),
    category_results AS (
        SELECT
            c.category_id,
            c.category_name,
            c.parent_id,
            CASE
                WHEN tree.category_id IS NOT NULL
                    THEN array_to_string(tree.name_path, ' > ')
                ELSE NULL
            END AS category_path,
            tree.depth,
            tree.category_id IS NOT NULL AS is_reachable,
            CASE
                WHEN tree.category_id IS NOT NULL
                    THEN coalesce(rollup.product_count, 0::bigint)
                ELSE coalesce(direct.product_count, 0::bigint)
            END AS low_stock_product_count,
            CASE
                WHEN tree.category_id IS NOT NULL
                    THEN coalesce(rollup.stock_units, 0::bigint)
                ELSE coalesce(direct.stock_units, 0::bigint)
            END AS low_stock_units,
            CASE
                WHEN tree.category_id IS NOT NULL
                    THEN 'category and reachable descendants'
                ELSE 'direct products only; category unreachable'
            END AS rollup_scope
        FROM public.categories AS c
        LEFT JOIN category_tree AS tree
          ON tree.category_id = c.category_id
        LEFT JOIN reachable_rollup AS rollup
          ON rollup.category_id = c.category_id
        LEFT JOIN direct_low_stock AS direct
          ON direct.category_id = c.category_id
    ),
    unassigned_products AS (
        SELECT
            count(*)::bigint AS product_count,
            sum(p.stock_quantity)::bigint AS stock_units
        FROM public.products AS p
        WHERE p.stock_quantity <= p_threshold
          AND (
              p.category_id IS NULL
              OR NOT EXISTS (
                  SELECT 1
                  FROM public.categories AS c
                  WHERE c.category_id = p.category_id
              )
          )
    ),
    all_results AS (
        SELECT
            cr.category_id,
            cr.category_name,
            cr.parent_id,
            cr.category_path,
            cr.depth,
            cr.is_reachable,
            cr.low_stock_product_count,
            cr.low_stock_units,
            cr.rollup_scope
        FROM category_results AS cr

        UNION ALL

        SELECT
            NULL::integer,
            'Uncategorized or missing category'::text,
            NULL::integer,
            NULL::text,
            NULL::integer,
            false,
            up.product_count,
            coalesce(up.stock_units, 0::bigint),
            'unassigned products'::text
        FROM unassigned_products AS up
        WHERE up.product_count > 0
    )
    SELECT
        result.category_id,
        result.category_name,
        result.parent_id,
        result.category_path,
        result.depth,
        result.is_reachable,
        result.low_stock_product_count,
        result.low_stock_units,
        result.rollup_scope
    FROM all_results AS result
    ORDER BY result.depth NULLS LAST, result.category_name;
END;
$function$;
