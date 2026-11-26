# Schema changes

These are solution scripts. Do not edit the supplied `data/schema.sql`.

## Run order

Run after loading the source data, in numeric order:

```powershell
docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/01_id_sequences.sql
docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/02_constraints.sql
docker exec kloudkart-db psql -U postgres -d kloudkart -v ON_ERROR_STOP=1 -f /sql/02_schema_changes/03_indexes.sql
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
- A foreign key on `categories.parent_id` does not prevent category cycles. Recursive queries must still track visited categories.
