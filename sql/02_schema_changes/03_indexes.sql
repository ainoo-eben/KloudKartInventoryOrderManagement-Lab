-- Index foreign-key and report lookup columns not covered by primary keys.
-- Run after schema.sql and load.sql.

CREATE INDEX IF NOT EXISTS categories_parent_id_idx
    ON public.categories (parent_id);

CREATE INDEX IF NOT EXISTS products_category_id_idx
    ON public.products (category_id);

CREATE INDEX IF NOT EXISTS orders_customer_order_date_idx
    ON public.orders (customer_id, order_date);

CREATE INDEX IF NOT EXISTS order_items_order_id_idx
    ON public.order_items (order_id);

CREATE INDEX IF NOT EXISTS order_items_product_id_idx
    ON public.order_items (product_id);

CREATE INDEX IF NOT EXISTS inventory_log_product_created_at_idx
    ON public.inventory_log (product_id, created_at DESC);
