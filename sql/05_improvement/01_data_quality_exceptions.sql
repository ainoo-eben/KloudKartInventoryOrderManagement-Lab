-- Data-quality exceptions for review; this function never changes source rows.
-- The as-of date is inclusive and controls which later-dated rows are flagged.

CREATE OR REPLACE FUNCTION public.data_quality_exceptions(
    p_as_of date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    issue_type text,
    source_table text,
    record_id bigint,
    details jsonb,
    assessment text,
    detection_query text
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '22004',
            MESSAGE = 'p_as_of cannot be NULL';
    END IF;

    RETURN QUERY
    WITH order_line_totals AS (
        SELECT
            oi.order_id,
            sum(oi.quantity * oi.unit_price) AS line_total,
            count(*)::bigint AS line_count
        FROM public.order_items AS oi
        GROUP BY oi.order_id
    ),
    inventory_totals AS (
        SELECT
            il.product_id,
            sum(il.change_qty) AS logged_net_change
        FROM public.inventory_log AS il
        GROUP BY il.product_id
    ),
    status_formatting_variants AS (
        SELECT
            o.status AS stored_status,
            lower(btrim(o.status)) AS normalized_status,
            count(*)::bigint AS affected_orders
        FROM public.orders AS o
        WHERE o.status IS NOT NULL
          AND o.status IS DISTINCT FROM lower(btrim(o.status))
        GROUP BY o.status
    ),
    unknown_status_values AS (
        SELECT
            o.status AS stored_status,
            lower(btrim(o.status)) AS normalized_status,
            count(*)::bigint AS affected_orders
        FROM public.orders AS o
        WHERE lower(btrim(o.status)) IS NULL
           OR lower(btrim(o.status)) NOT IN
              ('completed', 'complete', 'shipped', 'pending',
               'cancelled', 'canceled', 'refunded')
        GROUP BY o.status
    )
    SELECT
        'order_status_formatting_variant'::text,
        'orders'::text,
        NULL::bigint,
        jsonb_build_object(
            'stored_status', sv.stored_status,
            'normalized_status', sv.normalized_status,
            'affected_orders', sv.affected_orders
        ),
        'formatting differs; spending reports normalize this value'::text,
        format(
            $$SELECT order_id, status FROM orders
              WHERE status IS NOT DISTINCT FROM %L$$,
            sv.stored_status
        )
    FROM status_formatting_variants AS sv

    UNION ALL

    SELECT
        'unknown_order_status'::text,
        'orders'::text,
        NULL::bigint,
        jsonb_build_object(
            'stored_status', us.stored_status,
            'normalized_status', us.normalized_status,
            'affected_orders', us.affected_orders
        ),
        'requires review'::text,
        format(
            $$SELECT order_id, status FROM orders
              WHERE lower(btrim(status)) IS NOT DISTINCT FROM %L
                AND (
                    lower(btrim(status)) IS NULL
                    OR lower(btrim(status)) NOT IN
                       ('completed', 'complete', 'shipped', 'pending',
                        'cancelled', 'canceled', 'refunded')
                )$$,
            us.normalized_status
        )
    FROM unknown_status_values AS us

    UNION ALL

    SELECT
        'order_line_total_mismatch'::text,
        'orders'::text,
        o.order_id::bigint,
        jsonb_build_object(
            'order_total', o.total_amount,
            'line_total', olt.line_total,
            'difference', o.total_amount - olt.line_total,
            'line_count', coalesce(olt.line_count, 0)
        ),
        'requires review; neither amount is assumed correct'::text,
        $$SELECT o.order_id, o.total_amount, sum(oi.quantity * oi.unit_price)
          FROM orders AS o
          LEFT JOIN order_items AS oi ON oi.order_id = o.order_id
          GROUP BY o.order_id, o.total_amount
          HAVING o.total_amount IS DISTINCT FROM
                 sum(oi.quantity * oi.unit_price)$$::text
    FROM public.orders AS o
    LEFT JOIN order_line_totals AS olt
      ON olt.order_id = o.order_id
    WHERE o.total_amount IS DISTINCT FROM olt.line_total

    UNION ALL

    SELECT
        'missing_order_item_price'::text,
        'order_items'::text,
        oi.order_item_id::bigint,
        jsonb_build_object('order_id', oi.order_id, 'product_id', oi.product_id),
        'requires review; do not substitute the current product price'::text,
        $$SELECT order_item_id, order_id, product_id
          FROM order_items WHERE unit_price IS NULL$$::text
    FROM public.order_items AS oi
    WHERE oi.unit_price IS NULL

    UNION ALL

    SELECT
        'order_item_missing_order'::text,
        'order_items'::text,
        oi.order_item_id::bigint,
        jsonb_build_object('order_id', oi.order_id),
        'requires review'::text,
        $$SELECT oi.order_item_id, oi.order_id FROM order_items AS oi
          WHERE NOT EXISTS (
              SELECT 1 FROM orders AS o WHERE o.order_id = oi.order_id
          )$$::text
    FROM public.order_items AS oi
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.orders AS o
        WHERE o.order_id = oi.order_id
    )

    UNION ALL

    SELECT
        'order_item_missing_product'::text,
        'order_items'::text,
        oi.order_item_id::bigint,
        jsonb_build_object('product_id', oi.product_id),
        'requires review'::text,
        $$SELECT oi.order_item_id, oi.product_id FROM order_items AS oi
          WHERE NOT EXISTS (
              SELECT 1 FROM products AS p WHERE p.product_id = oi.product_id
          )$$::text
    FROM public.order_items AS oi
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.products AS p
        WHERE p.product_id = oi.product_id
    )

    UNION ALL

    SELECT
        'order_missing_customer'::text,
        'orders'::text,
        o.order_id::bigint,
        jsonb_build_object('customer_id', o.customer_id),
        'requires review'::text,
        $$SELECT o.order_id, o.customer_id FROM orders AS o
          WHERE NOT EXISTS (
              SELECT 1 FROM customers AS c WHERE c.customer_id = o.customer_id
          )$$::text
    FROM public.orders AS o
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.customers AS c
        WHERE c.customer_id = o.customer_id
    )

    UNION ALL

    SELECT
        'inventory_log_missing_product'::text,
        'inventory_log'::text,
        il.log_id::bigint,
        jsonb_build_object('product_id', il.product_id),
        'requires review'::text,
        $$SELECT il.log_id, il.product_id FROM inventory_log AS il
          WHERE NOT EXISTS (
              SELECT 1 FROM products AS p WHERE p.product_id = il.product_id
          )$$::text
    FROM public.inventory_log AS il
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.products AS p
        WHERE p.product_id = il.product_id
    )

    UNION ALL

    SELECT
        'product_missing_category'::text,
        'products'::text,
        p.product_id::bigint,
        jsonb_build_object('category_id', p.category_id),
        'requires review; category may be intentionally unassigned'::text,
        $$SELECT p.product_id, p.category_id FROM products AS p
          WHERE p.category_id IS NULL
             OR NOT EXISTS (
                 SELECT 1 FROM categories AS c
                 WHERE c.category_id = p.category_id
             )$$::text
    FROM public.products AS p
    WHERE p.category_id IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM public.categories AS c
           WHERE c.category_id = p.category_id
       )

    UNION ALL

    SELECT
        'category_missing_parent'::text,
        'categories'::text,
        c.category_id::bigint,
        jsonb_build_object('parent_id', c.parent_id),
        'requires review; do not reparent without business confirmation'::text,
        $$SELECT c.category_id, c.parent_id FROM categories AS c
          WHERE c.parent_id IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM categories AS parent
                WHERE parent.category_id = c.parent_id
            )$$::text
    FROM public.categories AS c
    WHERE c.parent_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.categories AS parent
          WHERE parent.category_id = c.parent_id
      )

    UNION ALL

    SELECT
        'order_after_as_of_date'::text,
        'orders'::text,
        o.order_id::bigint,
        jsonb_build_object('order_date', o.order_date, 'as_of_date', p_as_of),
        'requires date verification'::text,
        format(
            $$SELECT order_id, order_date FROM orders
              WHERE order_date >= (DATE %L + 1)::timestamp$$,
            p_as_of
        )
    FROM public.orders AS o
    WHERE o.order_date >= (p_as_of + 1)::timestamp

    UNION ALL

    SELECT
        'inventory_log_after_as_of_date'::text,
        'inventory_log'::text,
        il.log_id::bigint,
        jsonb_build_object('created_at', il.created_at, 'as_of_date', p_as_of),
        'requires date verification'::text,
        format(
            $$SELECT log_id, created_at FROM inventory_log
              WHERE created_at >= (DATE %L + 1)::timestamp$$,
            p_as_of
        )
    FROM public.inventory_log AS il
    WHERE il.created_at >= (p_as_of + 1)::timestamp

    UNION ALL

    SELECT
        'negative_product_stock'::text,
        'products'::text,
        p.product_id::bigint,
        jsonb_build_object('stock_quantity', p.stock_quantity),
        'requires review before correcting stock'::text,
        $$SELECT product_id, stock_quantity FROM products
          WHERE stock_quantity < 0$$::text
    FROM public.products AS p
    WHERE p.stock_quantity < 0

    UNION ALL

    SELECT
        'stock_differs_from_logged_net_change'::text,
        'products'::text,
        p.product_id::bigint,
        jsonb_build_object(
            'stock_quantity', p.stock_quantity,
            'logged_net_change', coalesce(it.logged_net_change, 0),
            'has_inventory_log', it.product_id IS NOT NULL
        ),
        'unverified; no trusted opening-stock baseline'::text,
        $$SELECT p.product_id, p.stock_quantity,
                 coalesce(sum(il.change_qty), 0) AS logged_net_change
          FROM products AS p
          LEFT JOIN inventory_log AS il ON il.product_id = p.product_id
          GROUP BY p.product_id, p.stock_quantity
          HAVING p.stock_quantity IS DISTINCT FROM
                 coalesce(sum(il.change_qty), 0)$$::text
    FROM public.products AS p
    LEFT JOIN inventory_totals AS it
      ON it.product_id = p.product_id
    WHERE p.stock_quantity IS DISTINCT FROM coalesce(it.logged_net_change, 0);
END;
$function$;
