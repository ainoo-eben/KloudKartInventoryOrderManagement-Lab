# Schema changes

These are solution scripts. Do not edit the supplied `data/schema.sql`.

## Run order

Run after loading the source data, in numeric order. Set `$DbName` to the
disposable database used for the lab; do not apply these commands to a
database containing records you need:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/01_id_sequences.sql
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/02_constraints.sql
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/03_indexes.sql
```

These scripts target the loaded `public` schema.

## What each script does

- `01_id_sequences.sql` creates defaults for order, order-item, and inventory-log IDs and advances each sequence beyond imported IDs. It does not allocate IDs with `max(id) + 1`.
- `02_constraints.sql` adds foreign keys and checks for nonnegative stock, positive order quantity, and a present, nonnegative receipt-line price. Constraints use `NOT VALID` so known legacy violations do not block installation. PostgreSQL still enforces them for new or changed rows.
- `03_indexes.sql` adds indexes for category traversal, report/order lookups, and inventory history.

## Existing-data caveats

- Existing negative stock, missing references, and NULL receipt-line prices are preserved; they are not silently repaired.
- The nonnegative-stock check cannot be validated until the 14 legacy negative-stock products are resolved. While a row violates a `NOT VALID` check, updating that row without fixing its stock value will fail the check.
- Foreign keys cannot be validated until their existing orphaned records are reviewed and resolved.
- No unique email constraint or status constraint is added. Duplicate customer emails and inconsistent historical statuses remain visible for the report and data-quality review.
  - **Downstream risk of not enforcing unique emails:** the spending report treats each `customer_id` as a separate customer. Where one person has several accounts (533 normalized duplicate-email groups covering 1,068 customer rows, GHS 9.7M of spend), their spending is split across rows, so they can rank lower than they should or miss the top 100, and the customer count is overstated. A unique constraint would fail on the existing rows and could block legitimate shared addresses, so the groups need a manual review and merge decision first (see `docs/02_key_decisions.md`, judgement call 8).
  - **Downstream risk of not constraining status:** a new spelling would load without error. The report counts only the mapped values as spend, so an unmapped spelling is excluded rather than miscounted, and it is listed by `data_quality_exceptions()` as an unknown status.
- A foreign key on `categories.parent_id` does not prevent category cycles. Recursive queries must still track visited categories.
