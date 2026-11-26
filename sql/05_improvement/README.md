# Improvement: data-quality exceptions

`01_data_quality_exceptions.sql` installs
`public.data_quality_exceptions(p_as_of date)`. It reports status formatting
variants and unknown statuses, order/line total differences, missing prices,
orphan references, dates after the as-of date, negative stock, and
stock-versus-log differences.

Run for the supplied extract's cutoff:

```sql
SELECT *
FROM public.data_quality_exceptions(DATE '2026-08-31')
ORDER BY issue_type, source_table, record_id;
```

With no argument, the function uses `CURRENT_DATE`. Pass an earlier date to
review a historical extract against its known cutoff. For date checks, rows
after the end of the given date are returned.

Each exception includes its observed values, review assessment, and a query
that can be used to verify the finding. Most findings identify one source row;
status variants are summarized by stored spelling and include the number of
affected orders, so a common capitalization difference does not produce
thousands of repetitive rows. The report never edits source data. Stock/log
differences are explicitly marked unverified because the extract does not
provide a trusted opening-stock balance. Orphan category assignments are
surfaced for review, not automatically repaired.

The function is installed by `sql/run_all.sql` after the source load and
schema changes.
