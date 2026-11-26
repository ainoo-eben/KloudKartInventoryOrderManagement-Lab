-- Protect new rows while preserving known legacy exceptions.
-- NOT VALID skips the initial scan of existing rows but checks new writes.
-- Run after schema.sql and load.sql.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'categories_parent_id_fkey'
          AND conrelid = 'public.categories'::regclass
    ) THEN
        ALTER TABLE public.categories
            ADD CONSTRAINT categories_parent_id_fkey
            FOREIGN KEY (parent_id)
            REFERENCES public.categories (category_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'products_category_id_fkey'
          AND conrelid = 'public.products'::regclass
    ) THEN
        ALTER TABLE public.products
            ADD CONSTRAINT products_category_id_fkey
            FOREIGN KEY (category_id)
            REFERENCES public.categories (category_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'orders_customer_id_fkey'
          AND conrelid = 'public.orders'::regclass
    ) THEN
        ALTER TABLE public.orders
            ADD CONSTRAINT orders_customer_id_fkey
            FOREIGN KEY (customer_id)
            REFERENCES public.customers (customer_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'order_items_order_id_fkey'
          AND conrelid = 'public.order_items'::regclass
    ) THEN
        ALTER TABLE public.order_items
            ADD CONSTRAINT order_items_order_id_fkey
            FOREIGN KEY (order_id)
            REFERENCES public.orders (order_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'order_items_product_id_fkey'
          AND conrelid = 'public.order_items'::regclass
    ) THEN
        ALTER TABLE public.order_items
            ADD CONSTRAINT order_items_product_id_fkey
            FOREIGN KEY (product_id)
            REFERENCES public.products (product_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'inventory_log_product_id_fkey'
          AND conrelid = 'public.inventory_log'::regclass
    ) THEN
        ALTER TABLE public.inventory_log
            ADD CONSTRAINT inventory_log_product_id_fkey
            FOREIGN KEY (product_id)
            REFERENCES public.products (product_id)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'products_stock_nonnegative_check'
          AND conrelid = 'public.products'::regclass
    ) THEN
        ALTER TABLE public.products
            ADD CONSTRAINT products_stock_nonnegative_check
            CHECK (stock_quantity >= 0)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'order_items_quantity_positive_check'
          AND conrelid = 'public.order_items'::regclass
    ) THEN
        ALTER TABLE public.order_items
            ADD CONSTRAINT order_items_quantity_positive_check
            CHECK (quantity > 0)
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'order_items_unit_price_valid_check'
          AND conrelid = 'public.order_items'::regclass
    ) THEN
        ALTER TABLE public.order_items
            ADD CONSTRAINT order_items_unit_price_valid_check
            CHECK (unit_price IS NOT NULL AND unit_price >= 0)
            NOT VALID;
    END IF;
END;
$$;
