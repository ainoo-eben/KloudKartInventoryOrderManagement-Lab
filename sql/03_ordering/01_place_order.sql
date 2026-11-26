-- Atomic order placement for the race_test.py contract.
-- Run after sql/02_schema_changes/01_id_sequences.sql.

CREATE OR REPLACE FUNCTION public.place_order(
    p_customer_id bigint,
    p_product_id bigint,
    p_quantity integer
)
RETURNS TABLE (
    success boolean,
    order_id bigint,
    message text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_unit_price numeric(12, 2);
    v_order_id bigint;
    v_ordered_at timestamp without time zone := clock_timestamp();
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RETURN QUERY
        SELECT false, NULL::bigint, 'quantity must be greater than zero'::text;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.customers c
        WHERE c.customer_id = p_customer_id
    ) THEN
        RETURN QUERY
        SELECT false, NULL::bigint, 'customer not found'::text;
        RETURN;
    END IF;

    -- The availability check and decrement happen in one UPDATE. Concurrent
    -- attempts for this product serialize on its row; after waiting, PostgreSQL
    -- rechecks the stock predicate against the latest committed value.
    UPDATE public.products AS p
    SET stock_quantity = p.stock_quantity - p_quantity
    WHERE p.product_id = p_product_id
      AND p_quantity > 0
      AND p.stock_quantity >= p_quantity
      AND p.price IS NOT NULL
      AND p.price >= 0
    RETURNING p.price INTO v_unit_price;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT false, NULL::bigint, 'out of stock or product unavailable'::text;
        RETURN;
    END IF;

    INSERT INTO public.orders (customer_id, order_date, status, total_amount)
    VALUES (
        p_customer_id,
        v_ordered_at,
        'completed',
        v_unit_price * p_quantity
    )
    RETURNING public.orders.order_id INTO v_order_id;

    INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_quantity, v_unit_price);

    INSERT INTO public.inventory_log
        (product_id, change_qty, reason, created_at, note)
    VALUES (
        p_product_id,
        -p_quantity,
        'sale',
        v_ordered_at,
        format('Order %s', v_order_id)
    );

    RETURN QUERY
    SELECT true, v_order_id, 'order placed'::text;
END
$function$;
