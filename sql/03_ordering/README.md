# Order placement

`01_place_order.sql` defines `public.place_order(bigint, bigint, integer)` with the return shape required by the supplied `data/race_test.py`.

The function:

1. Rejects invalid quantities and unknown customers without changing stock.
2. Decrements inventory using a conditional `UPDATE`, so concurrent attempts for the same product cannot both claim the last unit.
3. Creates the order, order item, and negative `sale` inventory movement in the same transaction.
4. Returns `success = false`, a NULL order ID, and a message containing “out of stock” when stock is insufficient or the product is unavailable.

If any database write fails after the stock update, PostgreSQL rolls back the function call's transaction, including that decrement. Order and log IDs use the sequences installed by `sql/02_schema_changes/01_id_sequences.sql`.

Apply after the source load and schema-change scripts. Use the same disposable
database selected in the project README:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/03_ordering/01_place_order.sql
```

Verify with the supplied test unchanged:

```powershell
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/$DbName"
.\.venv\Scripts\python.exe data\race_test.py
Remove-Item Env:DATABASE_URL
```

This assumes Python and `psycopg2-binary` are installed in the host virtual environment. The test removes its own fixtures unless `--keep-fixtures` is passed. The test opens 400 simultaneous connections for its flash-sale case; make sure PostgreSQL's configured connection limit has room for them.
