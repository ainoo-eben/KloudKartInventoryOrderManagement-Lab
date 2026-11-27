-- Every stock movement leaves a trail (Nana's criterion 4).
-- Run after 01_place_order.sql. See ADR-002.
--
-- Two layers:
--   1. adjust_stock(...)  - the supported path for restocks, returns,
--      corrections, damage write-offs and stock takes. It records the
--      business reason and a note, and cannot push stock below zero.
--   2. A safety-net trigger on products - if stock_quantity changes outside
--      place_order/adjust_stock (a manual UPDATE, an old script, a back-office
--      tool), the change is still logged as 'unlogged_direct_update' with who
--      made it. A new product inserted with stock gets an 'opening_stock'
--      movement, so future products have the reconciliation baseline that the
--      legacy data lacks.
--
-- The approved functions set the transaction-local flag
-- kloudkart.movement_logged = 'on' only around their own UPDATE, so the
-- trigger never double-logs their movement but still catches anything else.

CREATE OR REPLACE FUNCTION public.adjust_stock(
    p_product_id bigint,
    p_change integer,
    p_reason text,
    p_note text DEFAULT NULL
)
RETURNS TABLE (
    success boolean,
    log_id bigint,
    new_stock integer,
    message text
)
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_reason text := lower(btrim(p_reason));
    v_note text := nullif(btrim(p_note), '');
    v_new_stock integer;
    v_current integer;
    v_log_id bigint;
    v_at timestamp without time zone := clock_timestamp();
BEGIN
    IF v_reason IS NULL
       OR v_reason NOT IN ('restock', 'return', 'correction', 'damage', 'stock_take') THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            'invalid reason: use restock, return, correction, damage or stock_take'::text;
        RETURN;
    END IF;

    IF p_change IS NULL THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            'change quantity is required'::text;
        RETURN;
    END IF;

    -- Signs follow the conventions already present in the legacy log
    -- (see docs/01_data_diagnosis.md, finding 2).
    IF v_reason IN ('restock', 'return') AND p_change <= 0 THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            format('%s must add stock (positive change)', v_reason);
        RETURN;
    ELSIF v_reason = 'damage' AND p_change >= 0 THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            'damage must remove stock (negative change)'::text;
        RETURN;
    ELSIF v_reason = 'correction' AND p_change = 0 THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            'correction must change stock'::text;
        RETURN;
    END IF;

    IF v_reason IN ('correction', 'stock_take') AND v_note IS NULL THEN
        RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
            format('%s requires a note explaining who counted and why', v_reason);
        RETURN;
    END IF;

    PERFORM set_config('kloudkart.movement_logged', 'on', true);

    UPDATE public.products AS p
    SET stock_quantity = p.stock_quantity + p_change
    WHERE p.product_id = p_product_id
      AND p.stock_quantity + p_change >= 0
    RETURNING p.stock_quantity INTO v_new_stock;

    PERFORM set_config('kloudkart.movement_logged', '', true);

    IF v_new_stock IS NULL THEN
        SELECT p.stock_quantity INTO v_current
        FROM public.products AS p
        WHERE p.product_id = p_product_id;

        IF NOT FOUND THEN
            RETURN QUERY SELECT false, NULL::bigint, NULL::integer,
                'product not found'::text;
        ELSE
            RETURN QUERY SELECT false, NULL::bigint, v_current,
                format('refused: change of %s would leave stock below zero (current %s)',
                       p_change, coalesce(v_current::text, 'unknown'));
        END IF;
        RETURN;
    END IF;

    INSERT INTO public.inventory_log AS il
        (product_id, change_qty, reason, created_at, note)
    VALUES (p_product_id, p_change, v_reason, v_at, v_note)
    RETURNING il.log_id INTO v_log_id;

    RETURN QUERY SELECT true, v_log_id, v_new_stock, 'stock adjusted'::text;
END
$function$;


CREATE OR REPLACE FUNCTION public.log_unrecorded_stock_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_who text := format(
        'by %s via %s',
        current_user,
        coalesce(nullif(current_setting('application_name', true), ''), 'unknown application')
    );
BEGIN
    IF coalesce(current_setting('kloudkart.movement_logged', true), '') = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.inventory_log
            (product_id, change_qty, reason, created_at, note)
        VALUES (
            NEW.product_id,
            NEW.stock_quantity,
            'opening_stock',
            clock_timestamp(),
            'New product opening balance ' || v_who
        );
    ELSE
        INSERT INTO public.inventory_log
            (product_id, change_qty, reason, created_at, note)
        VALUES (
            NEW.product_id,
            coalesce(NEW.stock_quantity, 0) - coalesce(OLD.stock_quantity, 0),
            'unlogged_direct_update',
            clock_timestamp(),
            format('Stock changed outside adjust_stock/place_order (%s -> %s) %s',
                   OLD.stock_quantity, NEW.stock_quantity, v_who)
        );
    END IF;

    RETURN NULL;
END
$function$;

DROP TRIGGER IF EXISTS products_stock_opening_audit ON public.products;
CREATE TRIGGER products_stock_opening_audit
    AFTER INSERT ON public.products
    FOR EACH ROW
    WHEN (coalesce(NEW.stock_quantity, 0) <> 0)
    EXECUTE FUNCTION public.log_unrecorded_stock_change();

DROP TRIGGER IF EXISTS products_stock_change_audit ON public.products;
CREATE TRIGGER products_stock_change_audit
    AFTER UPDATE OF stock_quantity ON public.products
    FOR EACH ROW
    WHEN (OLD.stock_quantity IS DISTINCT FROM NEW.stock_quantity)
    EXECUTE FUNCTION public.log_unrecorded_stock_change();
