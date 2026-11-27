-- Add collision-safe ID generation for new orders and stock movements.
-- Run after schema.sql and load.sql so each sequence starts above imported IDs.
-- The original data/schema files remain unchanged.

CREATE SEQUENCE IF NOT EXISTS public.orders_order_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.order_items_order_item_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inventory_log_log_id_seq;

-- Why? If the table/column is dropped later:
--   PostgreSQL knows the sequence should go too. Without ownership, orphan sequences can be left behind.

ALTER SEQUENCE public.orders_order_id_seq
    OWNED BY public.orders.order_id;
ALTER SEQUENCE public.order_items_order_item_id_seq
    OWNED BY public.order_items.order_item_id;
ALTER SEQUENCE public.inventory_log_log_id_seq
    OWNED BY public.inventory_log.log_id;

ALTER TABLE public.orders
    ALTER COLUMN order_id
    SET DEFAULT nextval('public.orders_order_id_seq'::regclass);
ALTER TABLE public.order_items
    ALTER COLUMN order_item_id
    SET DEFAULT nextval('public.order_items_order_item_id_seq'::regclass);
ALTER TABLE public.inventory_log
    ALTER COLUMN log_id
    SET DEFAULT nextval('public.inventory_log_log_id_seq'::regclass);

DO $$
DECLARE
    item record;
    max_id bigint;
    sequence_value bigint;
    sequence_called boolean;
BEGIN
    FOR item IN
        SELECT *
        FROM (VALUES
            ('orders_order_id_seq', 'orders', 'order_id'),
            ('order_items_order_item_id_seq', 'order_items', 'order_item_id'),
            ('inventory_log_log_id_seq', 'inventory_log', 'log_id')
        ) AS ids(sequence_name, table_name, column_name)
    LOOP
        EXECUTE format(
            'SELECT max(%I)::bigint FROM public.%I',
            item.column_name,
            item.table_name
        )
        INTO max_id;

        EXECUTE format(
            'SELECT last_value, is_called FROM public.%I',
            item.sequence_name
        )
        INTO sequence_value, sequence_called;

        -- Preserve an already-advanced sequence on reruns, but move a new or
        -- lagging sequence past the highest imported/generated ID.
        IF max_id IS NOT NULL
           AND max_id > 0
           AND (NOT sequence_called OR max_id > sequence_value) THEN
            PERFORM setval(
                format('public.%I', item.sequence_name)::regclass,
                max_id,
                true
            );
        END IF;
    END LOOP;
END;
$$;
