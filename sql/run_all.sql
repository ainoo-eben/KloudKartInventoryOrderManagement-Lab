-- Apply the complete lab solution to a disposable, freshly loaded database.
-- Run with psql; this script drops/recreates the six source tables in the
-- currently selected database via the supplied data/schema.sql.
--
-- Because that is destructive, the script refuses to run unless the caller
-- confirms the target is disposable:
--
--     psql -d <disposable_db> -v ON_ERROR_STOP=1 -v confirm_reload=yes -f /sql/run_all.sql
--
-- It always refuses the persistent "kloudkart" database that docker-compose
-- creates, even with confirm_reload=yes.

\set ON_ERROR_STOP on
\cd /

\if :{?confirm_reload}
\else
    \set confirm_reload off
\endif

SELECT current_database() = 'kloudkart' AS target_is_persistent_db \gset

\if :target_is_persistent_db
    \echo 'REFUSED: run_all.sql would drop and reload the tables in the persistent "kloudkart" database.'
    \echo 'Create a disposable database (README step 4) and run it there.'
    DO $$ BEGIN RAISE EXCEPTION 'run_all.sql refused: target is the persistent kloudkart database'; END $$;
\elif :confirm_reload
    \echo 'confirm_reload=yes: dropping and reloading the source tables in' :DBNAME
\else
    \echo 'REFUSED: run_all.sql drops and reloads the six source tables in' :DBNAME
    \echo 'If this database is disposable, re-run with:  -v confirm_reload=yes'
    DO $$ BEGIN RAISE EXCEPTION 'run_all.sql refused: pass -v confirm_reload=yes for a disposable database'; END $$;
\endif

\echo 'Loading the supplied source schema and data'
\i /data/schema.sql
\i /data/load.sql

\echo 'Baseline row counts'
\i /sql/00_baseline/01_row_counts.sql

\echo 'Running the read-only data audits'
\i /sql/01_audit/01_nulls.sql
\i /sql/01_audit/02_duplicates.sql
\i /sql/01_audit/03_stock_issues.sql
\i /sql/01_audit/04_referential_integrity.sql
\i /sql/01_audit/05_category_issues.sql
\i /sql/01_audit/06_customer_issues.sql
\i /sql/01_audit/07_financial_issues.sql
\i /sql/01_audit/08_data_quality.sql
\i /sql/01_audit/09_financial_impact.sql

\echo 'Applying schema changes'
\i /sql/02_schema_changes/01_id_sequences.sql
\i /sql/02_schema_changes/02_constraints.sql
\i /sql/02_schema_changes/03_indexes.sql

\echo 'Installing order placement and reporting functions'
\i /sql/03_ordering/01_place_order.sql
\i /sql/03_ordering/02_stock_movements.sql
\i /sql/04_reporting/customer_spending_report.sql
\i /sql/04_reporting/low_stock_rollup.sql
\i /sql/05_improvement/01_data_quality_exceptions.sql

\echo 'Running self-checking validation (rolled back; fails the run on any broken behaviour)'
\i /sql/06_validation/01_assertions.sql

\echo 'Complete. The slow baseline EXPLAIN ANALYZE and concurrent race harness are separate experiments.'
