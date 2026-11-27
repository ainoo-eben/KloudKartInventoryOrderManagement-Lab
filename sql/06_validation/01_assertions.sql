-- Self-checking validation for the solution. Every check raises an error
-- (and, under ON_ERROR_STOP, stops the run) if the behaviour is wrong.
-- Everything runs inside one transaction that is rolled back, so the
-- database is left exactly as it was (sequences may advance; that is harmless).
--
-- Run after run_all.sql has installed the solution:
--   psql -v ON_ERROR_STOP=1 -f /sql/06_validation/01_assertions.sql

\set ON_ERROR_STOP on

BEGIN;

CREATE FUNCTION pg_temp.expect(p_ok boolean, p_what text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'VALIDATION FAILED: %', p_what;
    END IF;
    RAISE NOTICE 'ok  %', p_what;
END $$;

-- ---------------------------------------------------------------------------
-- A. Stock movement trail (Phase 2)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_pid bigint := (SELECT max(product_id) FROM products) + 5000;
    v_nopr bigint := v_pid + 1;
    v_cust bigint := (SELECT min(customer_id) FROM customers);
    r record;
    v_logs_before bigint;
BEGIN
    -- Fixture: new product with 5 units -> trigger logs an opening balance.
    INSERT INTO products (product_id, product_name, category_id, price, stock_quantity, created_at)
    VALUES (v_pid, 'VALIDATION FIXTURE', NULL, 10.00, 5, now());

    PERFORM pg_temp.expect(
        (SELECT count(*) = 1 AND sum(change_qty) = 5 FROM inventory_log
          WHERE product_id = v_pid AND reason = 'opening_stock'),
        'new product with stock writes one opening_stock movement');

    -- (a) A sale through place_order writes exactly one movement (no double log).
    SELECT * INTO r FROM place_order(v_cust, v_pid, 1);
    PERFORM pg_temp.expect(r.success AND r.order_id IS NOT NULL, 'place_order succeeds with stock available');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log WHERE product_id = v_pid) = 2,
        '(a) sale adds exactly one inventory_log row (trigger did not double-log)');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log
          WHERE product_id = v_pid AND reason = 'sale' AND change_qty = -1
            AND note = format('Order %s', r.order_id)) = 1,
        '(a) sale movement references its order');
    PERFORM pg_temp.expect(
        (SELECT stock_quantity FROM products WHERE product_id = v_pid) = 4,
        '(a) stock decremented to 4');

    -- (e) The "already logged" flag does not leak past place_order.
    PERFORM pg_temp.expect(
        coalesce(current_setting('kloudkart.movement_logged', true), '') = '',
        '(e) movement_logged flag is cleared after place_order returns');

    -- (b) Restock and correction through adjust_stock.
    SELECT * INTO r FROM adjust_stock(v_pid, 10, 'restock', 'PO 123 from supplier');
    PERFORM pg_temp.expect(r.success AND r.new_stock = 14, '(b) restock +10 -> 14');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log WHERE product_id = v_pid AND reason = 'restock' AND change_qty = 10) = 1,
        '(b) restock writes one +10 movement');

    SELECT * INTO r FROM adjust_stock(v_pid, -2, 'correction', 'Shelf count found 2 fewer');
    PERFORM pg_temp.expect(r.success AND r.new_stock = 12, '(b) correction -2 -> 12');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log WHERE product_id = v_pid AND reason = 'correction' AND change_qty = -2) = 1,
        '(b) correction writes one -2 movement');
    PERFORM pg_temp.expect(
        coalesce(current_setting('kloudkart.movement_logged', true), '') = '',
        '(e) movement_logged flag is cleared after adjust_stock returns');

    -- (c) A write-off larger than stock is refused; nothing changes.
    SELECT count(*) INTO v_logs_before FROM inventory_log WHERE product_id = v_pid;
    SELECT * INTO r FROM adjust_stock(v_pid, -100, 'damage', 'Flood');
    PERFORM pg_temp.expect(NOT r.success AND r.message LIKE 'refused%', '(c) damage -100 refused');
    PERFORM pg_temp.expect(
        (SELECT stock_quantity FROM products WHERE product_id = v_pid) = 12,
        '(c) stock unchanged after refused write-off');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log WHERE product_id = v_pid) = v_logs_before,
        '(c) refused write-off writes no movement');

    -- (f) Bad requests are refused cleanly.
    SELECT * INTO r FROM adjust_stock(v_pid, 5, 'gift', 'x');
    PERFORM pg_temp.expect(NOT r.success AND r.message LIKE 'invalid reason%', '(f) unknown reason refused');
    SELECT * INTO r FROM adjust_stock(v_pid, 5, 'correction', NULL);
    PERFORM pg_temp.expect(NOT r.success AND r.message LIKE '%requires a note%', '(f) correction without note refused');
    SELECT * INTO r FROM adjust_stock(v_pid, -5, 'restock', 'x');
    PERFORM pg_temp.expect(NOT r.success, '(f) negative restock refused');
    SELECT * INTO r FROM adjust_stock(v_pid, 5, 'damage', 'x');
    PERFORM pg_temp.expect(NOT r.success, '(f) positive damage refused');
    SELECT * INTO r FROM adjust_stock(v_pid + 999999, 5, 'restock', 'x');
    PERFORM pg_temp.expect(NOT r.success AND r.message = 'product not found', '(f) unknown product refused');

    -- (d) A raw UPDATE outside the functions is still caught by the trigger.
    UPDATE products SET stock_quantity = 20 WHERE product_id = v_pid;
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM inventory_log
          WHERE product_id = v_pid AND reason = 'unlogged_direct_update' AND change_qty = 8) = 1,
        '(d) direct UPDATE 12 -> 20 logged as unlogged_direct_update +8');
    PERFORM pg_temp.expect(
        (SELECT count(*) FROM data_quality_exceptions(DATE '2026-08-31')
          WHERE issue_type = 'stock_changed_outside_approved_process'
            AND (details->>'product_id')::bigint = v_pid) = 1,
        '(d) data_quality_exceptions flags the direct stock change for review');

    -- The trail now reconciles exactly: opening + all movements = stock.
    PERFORM pg_temp.expect(
        (SELECT sum(change_qty) FROM inventory_log WHERE product_id = v_pid)
          = (SELECT stock_quantity FROM products WHERE product_id = v_pid),
        'new product: sum of movements equals current stock (full reconciliation)');

    -- place_order refusal messages.
    SELECT * INTO r FROM place_order(v_cust, v_pid, 999);
    PERFORM pg_temp.expect(NOT r.success AND r.order_id IS NULL AND r.message = 'out of stock',
        'place_order: too many units -> "out of stock"');
    SELECT * INTO r FROM place_order(v_cust, v_pid + 999999, 1);
    PERFORM pg_temp.expect(NOT r.success AND r.message = 'product not found',
        'place_order: unknown product -> "product not found"');
    INSERT INTO products (product_id, product_name, category_id, price, stock_quantity, created_at)
    VALUES (v_nopr, 'VALIDATION FIXTURE NO PRICE', NULL, NULL, 5, now());
    SELECT * INTO r FROM place_order(v_cust, v_nopr, 1);
    PERFORM pg_temp.expect(NOT r.success AND r.message = 'product unavailable: no price set',
        'place_order: unpriced product -> "no price set", not "out of stock"');
    SELECT * INTO r FROM place_order(v_cust, v_pid, 0);
    PERFORM pg_temp.expect(NOT r.success, 'place_order: zero quantity refused');
END $$;

ROLLBACK;
