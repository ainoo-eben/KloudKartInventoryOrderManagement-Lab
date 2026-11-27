-- Apply the complete lab solution to a disposable, freshly loaded database.
-- Run with psql; this script drops/recreates the six source tables in the
-- currently selected database via the supplied data/schema.sql.

\set ON_ERROR_STOP on
\cd /

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
