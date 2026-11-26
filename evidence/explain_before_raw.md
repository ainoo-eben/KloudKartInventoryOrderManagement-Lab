# Raw Before-Report Output

The plan below is the original PostgreSQL output. The actual `EXPLAIN ANALYZE` attempt was canceled at the 120-second timeout.

```text
Baseline report: representative query, all statuses, recorded order totals; performance proxy only.
--- Estimated plan (EXPLAIN only; does not execute the report) ---
                                                                                                                                      QUERY PLAN                                                                                                                                      
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=132593213.52..133816410.77 rows=100 width=89)
   Output: c.customer_id, c.full_name, (COALESCE((SubPlan 1), '0'::numeric)), ((SubPlan 2)), (COALESCE((SubPlan 3), '[]'::jsonb))
   ->  Result  (cost=132593213.52..627009541.97 rows=40420 width=89)
         Output: c.customer_id, c.full_name, (COALESCE((SubPlan 1), '0'::numeric)), (SubPlan 2), COALESCE((SubPlan 3), '[]'::jsonb)
         ->  Sort  (cost=132593213.52..132593314.57 rows=40420 width=49)
               Output: c.customer_id, c.full_name, (COALESCE((SubPlan 1), '0'::numeric))
               Sort Key: (COALESCE((SubPlan 1), '0'::numeric)) DESC
               ->  Seq Scan on public.customers c  (cost=0.00..132591668.70 rows=40420 width=49)
                     Output: c.customer_id, c.full_name, COALESCE((SubPlan 1), '0'::numeric)
                     SubPlan 1
                       ->  Aggregate  (cost=3280.32..3280.33 rows=1 width=32)
                             Output: sum(o.total_amount)
                             ->  Seq Scan on public.orders o  (cost=0.00..3280.30 rows=5 width=7)
                                   Output: o.order_id, o.customer_id, o.order_date, o.status, o.total_amount
                                   Filter: (o.customer_id = c.customer_id)
         SubPlan 2
           ->  Aggregate  (cost=3280.31..3280.32 rows=1 width=8)
                 Output: count(*)
                 ->  Seq Scan on public.orders o_1  (cost=0.00..3280.30 rows=5 width=0)
                       Output: o_1.order_id, o_1.customer_id, o_1.order_date, o_1.status, o_1.total_amount
                       Filter: (o_1.customer_id = c.customer_id)
         SubPlan 3
           ->  Aggregate  (cost=5671.30..5671.31 rows=1 width=32)
                 Output: jsonb_agg(jsonb_build_object('month', ((date_trunc('month'::text, o_2.order_date))::date), 'monthly_spend', (sum(o_2.total_amount)), 'running_spend', (sum((sum(o_2.total_amount))) OVER (?))) ORDER BY ((date_trunc('month'::text, o_2.order_date))::date))
                 ->  WindowAgg  (cost=5671.12..5671.28 rows=4 width=68)
                       Output: ((date_trunc('month'::text, o_2.order_date))::date), (sum(o_2.total_amount)), sum((sum(o_2.total_amount))) OVER (?)
                       ->  GroupAggregate  (cost=5671.12..5671.22 rows=4 width=36)
                             Output: ((date_trunc('month'::text, o_2.order_date))::date), sum(o_2.total_amount)
                             Group Key: ((date_trunc('month'::text, o_2.order_date))::date)
                             ->  Sort  (cost=5671.12..5671.13 rows=4 width=11)
                                   Output: ((date_trunc('month'::text, o_2.order_date))::date), o_2.total_amount
                                   Sort Key: ((date_trunc('month'::text, o_2.order_date))::date)
                                   ->  Seq Scan on public.orders o_2  (cost=0.00..5671.08 rows=4 width=11)
                                         Output: (date_trunc('month'::text, o_2.order_date))::date, o_2.total_amount
                                         Filter: ((o_2.customer_id = c.customer_id) AND (o_2.order_date >= (CURRENT_DATE - '1 year'::interval)) AND (o_2.order_date < (CURRENT_DATE + '1 day'::interval)))
 JIT:
   Functions: 36
   Options: Inlining true, Optimization true, Expressions true, Deforming true
(38 rows)

--- Actual EXPLAIN ANALYZE attempt (120-second statement timeout) ---
SET
ERROR: canceling statement due to statement timeout
Observed runtime: 00:02:00.2614895; psql exit code: 3.
```
