-- Naive "before" report (same shape as 02_naive_report.sql) restricted to the
-- first :sample customers, so its cost per customer can be measured without
-- waiting for the full run. Used by scripts/benchmark.ps1.
--
-- Unlike 02_naive_report.sql this has NO final LIMIT 100: the brief asks for
-- every customer's totals and monthly breakdown, which is what the new report
-- returns. With LIMIT 100 the monthly sub-query only runs for 100 rows, which
-- would make the naive query look cheaper than a like-for-like comparison.
--
--   psql -v sample=500 -f /sql/00_baseline/04_naive_report_sample.sql

EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON)
SELECT
    c.customer_id,
    c.full_name,
    coalesce((
        SELECT sum(o.total_amount)
        FROM orders o
        WHERE o.customer_id = c.customer_id
    ), 0) AS recorded_spend_all_statuses,
    (
        SELECT count(*)
        FROM orders o
        WHERE o.customer_id = c.customer_id
    ) AS order_count_all_statuses,
    coalesce((
        SELECT jsonb_agg(
            jsonb_build_object(
                'month', m.month_start,
                'monthly_spend', m.monthly_spend,
                'running_spend', m.running_spend
            )
            ORDER BY m.month_start
        )
        FROM (
            SELECT
                monthly.month_start,
                monthly.monthly_spend,
                sum(monthly.monthly_spend) OVER (
                    ORDER BY monthly.month_start
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS running_spend
            FROM (
                SELECT
                    date_trunc('month', o.order_date)::date AS month_start,
                    sum(o.total_amount) AS monthly_spend
                FROM orders o
                WHERE o.customer_id = c.customer_id
                  AND o.order_date >= current_date - interval '12 months'
                  AND o.order_date < current_date + interval '1 day'
                GROUP BY date_trunc('month', o.order_date)::date
            ) monthly
        ) m
    ), '[]'::jsonb) AS trailing_12_months
FROM (
    SELECT * FROM customers ORDER BY customer_id LIMIT :sample
) c
ORDER BY recorded_spend_all_statuses DESC;
