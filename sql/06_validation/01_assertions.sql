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

-- ---------------------------------------------------------------------------
-- B. Customer spending report (Phase 3). Figures are for the supplied extract
--    at the documented 2026-08-31 cutoff; they are checked against a fresh
--    load, before any test orders are placed.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE report_check ON COMMIT DROP AS
SELECT * FROM customer_spending_report(DATE '2026-08-31');

DO $$
BEGIN
    PERFORM pg_temp.expect((SELECT count(*) FROM report_check) = (SELECT count(*) FROM customers),
        'report returns one row per customer');
    PERFORM pg_temp.expect(
        (SELECT min(customer_rank) = 1 AND max(customer_rank) = count(*)
                AND count(DISTINCT customer_rank) = count(*) FROM report_check),
        'ranks are 1..N with no gaps or ties');
    PERFORM pg_temp.expect((SELECT count(*) FROM report_check WHERE is_top_100) = 100,
        'exactly 100 customers flagged top-100');
    PERFORM pg_temp.expect(
        (SELECT bool_and(jsonb_array_length(trailing_12_months) = 12) FROM report_check),
        'every customer has exactly 12 monthly entries');
    PERFORM pg_temp.expect(
        (SELECT bool_and((trailing_12_months->11->>'lifetime_running_spend')::numeric = total_spent)
           FROM report_check),
        'final month lifetime_running_spend equals total_spent for every customer');
    PERFORM pg_temp.expect(
        (SELECT bool_and((trailing_12_months->11->>'running_spend')::numeric
                 = (SELECT sum((m->>'spend')::numeric) FROM jsonb_array_elements(trailing_12_months) m))
           FROM report_check),
        'running_spend in the final month equals the sum of the 12 monthly values');
    -- 159,360 = 159,384 loaded orders minus the 24 dated after the cutoff.
    -- Section A's test order is dated today (after the cutoff), so it does
    -- not affect this check.
    IF (SELECT count(*) FROM orders WHERE order_date < TIMESTAMP '2026-09-01') = 159360 THEN
        PERFORM pg_temp.expect((SELECT sum(total_spent) FROM report_check) = 380090162.62,
            'fresh load: total reported spend = 380,090,162.62 (unchanged from reporting_after.md)');
    ELSE
        RAISE NOTICE 'skip fresh-load total check: orders table has been modified since load';
    END IF;
END $$;

ROLLBACK;
