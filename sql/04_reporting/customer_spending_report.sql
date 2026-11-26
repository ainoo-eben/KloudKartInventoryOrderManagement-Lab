-- Customer spending report.
-- Spending statuses and amount source follow ADR-003 and ADR-004.
-- The as-of date defaults to the supplied extract's cutoff (ADR-005).

CREATE OR REPLACE FUNCTION public.customer_spending_report(
    p_as_of date DEFAULT DATE '2026-08-31'
)
RETURNS TABLE (
    customer_id integer,
    full_name text,
    total_spent numeric,
    order_count bigint,
    customer_rank bigint,
    is_top_100 boolean,
    trailing_12_months jsonb
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
    WITH bounds AS (
        SELECT
            p_as_of AS as_of_date,
            (date_trunc('month', p_as_of::timestamp)::date - interval '11 months')::date
                AS first_month,
            date_trunc('month', p_as_of::timestamp)::date AS last_month
    ),
    eligible_orders AS MATERIALIZED (
        SELECT
            o.customer_id,
            o.order_date,
            o.total_amount
        FROM public.orders AS o
        CROSS JOIN bounds AS b
        WHERE o.order_date < (b.as_of_date + 1)::timestamp
          AND lower(btrim(o.status)) IN ('completed', 'complete', 'shipped')
    ),
    customer_totals AS (
        SELECT
            eo.customer_id,
            sum(eo.total_amount) AS total_spent,
            count(*)::bigint AS order_count
        FROM eligible_orders AS eo
        GROUP BY eo.customer_id
    ),
    monthly_sales AS (
        SELECT
            eo.customer_id,
            date_trunc('month', eo.order_date)::date AS month_start,
            sum(eo.total_amount) AS monthly_spend
        FROM eligible_orders AS eo
        CROSS JOIN bounds AS b
        WHERE eo.order_date >= b.first_month::timestamp
        GROUP BY eo.customer_id, date_trunc('month', eo.order_date)::date
    ),
    month_spine AS (
        SELECT generated.month_start::date AS month_start
        FROM bounds AS b
        CROSS JOIN LATERAL generate_series(
            b.first_month::timestamp,
            b.last_month::timestamp,
            interval '1 month'
        ) AS generated(month_start)
    ),
    customer_months AS (
        SELECT
            c.customer_id,
            ms.month_start,
            coalesce(s.monthly_spend, 0::numeric) AS monthly_spend
        FROM public.customers AS c
        CROSS JOIN month_spine AS ms
        LEFT JOIN monthly_sales AS s
          ON s.customer_id = c.customer_id
         AND s.month_start = ms.month_start
    ),
    monthly_running AS (
        SELECT
            cm.customer_id,
            cm.month_start,
            cm.monthly_spend,
            sum(cm.monthly_spend) OVER (
                PARTITION BY cm.customer_id
                ORDER BY cm.month_start
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_spend
        FROM customer_months AS cm
    ),
    monthly_payload AS (
        SELECT
            mr.customer_id,
            jsonb_agg(
                jsonb_build_object(
                    'month', to_char(mr.month_start, 'YYYY-MM'),
                    'spend', mr.monthly_spend,
                    'running_spend', mr.running_spend
                )
                ORDER BY mr.month_start
            ) AS trailing_12_months
        FROM monthly_running AS mr
        GROUP BY mr.customer_id
    ),
    customer_report AS (
        SELECT
            c.customer_id,
            c.full_name,
            coalesce(ct.total_spent, 0::numeric) AS total_spent,
            coalesce(ct.order_count, 0::bigint) AS order_count,
            coalesce(mp.trailing_12_months, '[]'::jsonb) AS trailing_12_months
        FROM public.customers AS c
        LEFT JOIN customer_totals AS ct
          ON ct.customer_id = c.customer_id
        LEFT JOIN monthly_payload AS mp
          ON mp.customer_id = c.customer_id
    ),
    ranked_customers AS (
        SELECT
            cr.customer_id,
            cr.full_name,
            cr.total_spent,
            cr.order_count,
            row_number() OVER (
                ORDER BY cr.total_spent DESC, cr.customer_id
            ) AS customer_rank,
            cr.trailing_12_months
        FROM customer_report AS cr
    )
    SELECT
        rc.customer_id,
        rc.full_name,
        rc.total_spent,
        rc.order_count,
        rc.customer_rank,
        rc.customer_rank <= 100,
        rc.trailing_12_months
    FROM ranked_customers AS rc
    ORDER BY rc.customer_rank;
END;
$function$;
