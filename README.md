# Kloud Kart Inventory and Order Management Lab

This project investigates and improves a PostgreSQL order and inventory
database for Kloud Kart Ltd. It is a reproducible lab: the supplied source
records are loaded, audited, and used to test the SQL solution on a disposable
database running on the existing local PostgreSQL container.

The work focuses on four business needs:

1. Prevent two simultaneous orders from selling the same last unit.
2. Produce a customer-spending report quickly, including monthly totals,
   running totals, and a top-100 ranking.
3. Show low-stock products through a category hierarchy of any depth.
4. Make stock movements and data-quality problems easier to investigate.

## What is implemented

| Need | Implementation | Validation |
|---|---|---|
| Prevent overselling | `public.place_order(...)` uses a conditional stock update and writes the order, order item, and sale movement in the same transaction. | The supplied race test passed 25 last-unit rounds and a 400-buyer/50-unit sale. See [race-test evidence](evidence/race_test_runs.md). |
| Customer spending | `public.customer_spending_report(...)` returns customers, lifetime totals, order counts, twelve calendar-month totals, running monthly totals, and top-100 ranking. | 40,420 customers returned in about 3.85 seconds on the validation machine. See [reporting evidence](evidence/reporting_after.md). |
| Low-stock rollup | `public.low_stock_rollup(...)` recursively follows the category tree and guards against cycles. | 95 output rows in about 6 ms on the validation machine. |
| Data-quality review | `public.data_quality_exceptions(...)` reports known exceptions without modifying source data. | See [data-quality evidence](evidence/data_quality_report.md). |

These are lab results, not a production deployment. The checkout application
must call `place_order` for the overselling protection to apply. Also, only
sales made through that function are guaranteed to write an inventory-log
entry; other stock changes, such as restocks or corrections, are not yet
centrally forced through a logged operation.

## Project layout

```text
.
|-- data/                       Supplied source bundle; do not edit
|   |-- schema.sql
|   |-- load.sql
|   |-- race_test.py
|   |-- categories.csv
|   |-- products.csv
|   |-- customers.csv
|   |-- orders.csv
|   |-- order_items.csv
|   `-- inventory_log.csv
|-- sql/
|   |-- 00_baseline/             Starting counts and deliberately unsafe examples
|   |-- 01_audit/                Read-only data-quality checks
|   |-- 02_schema_changes/       Sequences, constraints, and indexes
|   |-- 03_ordering/             Atomic order placement
|   |-- 04_reporting/            Customer and low-stock reports
|   |-- 05_improvement/          Data-quality exceptions report
|   `-- run_all.sql              Fresh-load solution runner
|-- docs/                        Diagnosis, decisions, and memo
|-- decisions/                   Architecture decision records
|-- evidence/                    Captured test and performance results
|-- scripts/                     Baseline race demonstration
|-- docker-compose.yml
|-- requirements.txt             Host-side Python test dependency
`-- README.md
```

### The supplied data bundle

The contents of `data/` are excluded from Git by `.gitignore` because they are
the supplied input bundle, not solution files. A fresh clone may therefore
not contain them. Before running the project, obtain the bundle from the lab
materials and place the files directly in `data/` as shown above. The CSVs
must be alongside `load.sql`; do not put them in a nested `csv/` directory.

Do not edit `data/schema.sql`, `data/load.sql`, `data/race_test.py`, or the
supplied CSVs. The Docker Compose file mounts the source bundle read-only.

## Prerequisites

- Docker Desktop with Docker Compose, or a compatible Docker Engine and
  Compose plugin.
- A free local TCP port `5432` for PostgreSQL. If it is already in use, see
  [Troubleshooting](#troubleshooting).
- Python 3.8 or newer only if you intend to run the supplied Python race test.
  The SQL solution itself runs inside the PostgreSQL Docker container; you do
  not need to install `psql` on the host.
- PowerShell for the commands below on Windows. The same Docker and SQL steps
  work on macOS/Linux after adapting shell-variable and environment-variable
  syntax.

The Compose file starts PostgreSQL 16 with local lab credentials
(`postgres` / `postgres`). These credentials are for local testing only, not
for a public or production server.

## Reproduce the complete solution

Run these commands from the repository root in PowerShell.

### 1. Check that the input bundle is present

```powershell
Get-ChildItem .\data
```

You should see the two SQL files, `race_test.py`, and all six CSV files. If
they are missing, get the original bundle before continuing.

### 2. Create the local Python environment (for the race test)

This step is only required for `data/race_test.py`.

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

`requirements.txt` installs `psycopg2-binary`, the PostgreSQL driver imported
by the supplied test. You do not need to activate the environment; the
commands in this guide call its Python executable directly.

On macOS/Linux, create and install into the environment with:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

### 3. Start PostgreSQL

```powershell
docker compose up -d db
docker compose ps
docker exec kloudkart-db pg_isready -U postgres
```

Wait until `pg_isready` reports that the server is accepting connections. The
database files persist in the Compose volume named `pgdata`; stopping the
container does not erase them.

### 4. Create a disposable lab database

`sql/run_all.sql` runs the supplied `schema.sql`, which drops and recreates the
source tables in the database selected by `psql`. **Never run it against a
database containing records you need.** Use a disposable database on this
local PostgreSQL instance:

```powershell
$DbName = "kloudkart_lab"
docker exec kloudkart-db createdb -U postgres $DbName
if ($LASTEXITCODE -ne 0) {
    throw "Database creation failed. Choose a new disposable database name if it already exists."
}
```

If `kloudkart_lab` already exists, choose another name, such as
`kloudkart_lab_2`. Do not drop a database unless you have verified it is
disposable.

### 5. Load, audit, and install the solution

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -f /sql/run_all.sql
if ($LASTEXITCODE -ne 0) {
    throw "The SQL runner failed. Read the PostgreSQL error above before continuing."
}
```

`-X` prevents a local `psql` startup file from changing the run, and
`ON_ERROR_STOP=1` stops at the first SQL error. The runner performs these
steps in order:

1. Recreates the six source tables from `data/schema.sql`.
2. Loads the CSVs using the supplied `data/load.sql`.
3. Prints the baseline row counts and runs the eight read-only audit files.
4. Adds ID sequences, non-validating constraints, and indexes.
5. Installs `place_order`, the two business reports, and the data-quality
   exceptions function.

Expected source row counts:

| Table | Rows |
|---|---:|
| `categories` | 94 |
| `products` | 4,023 |
| `customers` | 40,420 |
| `orders` | 159,384 |
| `order_items` | 336,559 |
| `inventory_log` | 282,352 |

The audits intentionally report legacy problems; those findings are not
runner failures. The constraints use `NOT VALID` where required so known
legacy exceptions remain in place while applicable new or changed rows are
checked.

The runner does not execute the deliberately slow baseline report or the
concurrency experiments. Those are separate tests described below.

## Run and understand the reports

The examples below run against the `$DbName` database created above. The
`2026-08-31` as-of date is the documented cutoff for this supplied extract;
use another date only when appropriate for the data being reviewed.

### Customer-spending report

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -c "SELECT count(*) AS customers, count(*) FILTER (WHERE is_top_100) AS top_100, max(customer_rank) AS final_rank FROM public.customer_spending_report(DATE '2026-08-31');"
```

Expected on the supplied data: **40,420 customers**, **100 top-100 flags**,
and ranks ending at **40,420**. The report's measured runtime was about
**3.85 seconds** on the validation machine. Timings vary with hardware.

The result uses stored `orders.total_amount` and counts normalized
`completed`, `complete`, and `shipped` statuses as spending. It excludes
orders after the as-of date and includes customers with no qualifying orders.
These are documented assumptions, not verified payment facts.

For the full rows or monthly JSON values, remove the aggregate query above
and run:

```sql
SELECT *
FROM public.customer_spending_report(DATE '2026-08-31')
ORDER BY customer_rank;
```

### Low-stock category rollup

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -c "SELECT count(*) AS output_rows, count(*) FILTER (WHERE is_reachable) AS reachable_categories, count(*) FILTER (WHERE category_id IS NOT NULL AND NOT is_reachable) AS unreachable_categories, count(*) FILTER (WHERE category_id IS NULL) AS unassigned_buckets FROM public.low_stock_rollup(10);"
```

Expected on the supplied data: **95 rows**—91 reachable categories, 3
unreachable categories, and 1 unassigned/missing-category bucket. The default
threshold is **10 units**; change it by passing another nonnegative integer,
for example `public.low_stock_rollup(5)`.

Reachable categories include reachable descendants. A product can therefore
appear in several ancestor totals; do not add every category's count to get a
distinct product total. Unreachable categories receive direct-product counts
only, and unassigned products appear in their own row. The validated runtime
was about **6 ms**.

### Data-quality exceptions report

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -c "SELECT issue_type, count(*) AS report_rows, sum(coalesce((details->>'affected_orders')::bigint, 1)) AS affected_records FROM public.data_quality_exceptions(DATE '2026-08-31') GROUP BY issue_type ORDER BY issue_type;"
```

On the supplied data this returned **3,864 report rows** covering **94,756
affected records**. Status formatting variants are grouped by their stored
spelling, rather than producing one repeated row per order. The report also
includes a query with each finding so it can be checked. It does not repair
data.

Use the chosen cutoff when reviewing this historical extract. With no
argument, the function uses `CURRENT_DATE`, which is more appropriate for
reviewing current data:

```sql
SELECT *
FROM public.data_quality_exceptions(DATE '2026-08-31')
ORDER BY issue_type, source_table, record_id;
```

The 144 stock/log differences in this extract are **unverified**: the supplied
data does not establish a trusted opening-stock balance.

### Optional order-placement smoke test

This makes a real order and reduces the selected product's stock in the
database. Run it only on the disposable `$DbName` database:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -c "SELECT * FROM public.place_order((SELECT min(customer_id)::bigint FROM customers), (SELECT product_id::bigint FROM products WHERE stock_quantity > 0 AND price IS NOT NULL AND price >= 0 ORDER BY product_id LIMIT 1), 1);"
```

Success returns `success = true`, a new order ID, and `order placed`. The
function also writes one order item and one negative `sale` movement in the
same transaction. If a selected product has insufficient stock, it refuses
the order without creating those rows.

## Run the supplied concurrency test

The supplied `data/race_test.py` is the authoritative test for order
placement. It is run from the host, connects to the Docker database, and
cleans up its own test fixtures. Do not edit the test.

Check the server connection limit before starting. The test opens 400
simultaneous connections:

```powershell
$OriginalMax = (docker exec kloudkart-db psql -X -U postgres -d postgres -At -c "SHOW max_connections").Trim()
$OriginalMax
```

In the recorded run, PostgreSQL's limit was temporarily raised from 100 to
450 to accommodate the test, then restored. If your limit is below 450, only
raise it on a local lab container that you can restart. This changes a
server-wide setting and interrupts connections. Record the current value,
temporarily set 450, restart, and wait until `pg_isready` reports ready:

```powershell
if ([int]$OriginalMax -lt 450) {
    docker exec kloudkart-db psql -U postgres -d postgres -c "ALTER SYSTEM SET max_connections = 450;"
    docker restart kloudkart-db
    docker exec kloudkart-db pg_isready -U postgres
}
```

Run the test:

```powershell
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/$DbName"
.\.venv\Scripts\python.exe data\race_test.py
$RaceExit = $LASTEXITCODE
Remove-Item Env:DATABASE_URL
```

If you changed the connection limit, restore the original value you recorded
before continuing, then restart and wait for PostgreSQL to become ready:

```powershell
if ([int]$OriginalMax -lt 450) {
    docker exec kloudkart-db psql -U postgres -d postgres -c "ALTER SYSTEM SET max_connections = $OriginalMax;"
    docker restart kloudkart-db
    docker exec kloudkart-db pg_isready -U postgres
}
if ($RaceExit -ne 0) {
    throw "The supplied race test failed."
}
```

Do not leave the temporary value in place. Do not restart a shared or
production database to run this local lab test.

On macOS/Linux, set the connection string and run the test with the virtual
environment's Python:

```sh
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/kloudkart_lab"
.venv/bin/python data/race_test.py
unset DATABASE_URL
```

Expected test results:

- Test 1: one winner per last unit in all 25 rounds.
- Test 2: 50 successful orders and 350 clean refusals from 400 buyers.
- Test 3: an order exceeding available stock is refused without changing
  stock.
- Test 4: each successful order has its inventory movement.

The recorded run completed the 400-buyer case in **2.65 seconds** with no
errors. See [race_test_runs.md](evidence/race_test_runs.md) for the captured
output.

## Optional baseline experiments

These experiments demonstrate why the solution was needed. They are not part
of `run_all.sql`.

### Slow baseline report

`sql/00_baseline/02_naive_report.sql` uses `EXPLAIN ANALYZE`, which executes
the deliberately naive query. It may run for a long time. On the validation
data it did not finish within a 120-second statement timeout. Run only on a
disposable database:

```powershell
docker exec kloudkart-db psql -X -U postgres -d $DbName -c "SET statement_timeout = '120s';" -f /sql/00_baseline/02_naive_report.sql
```

A timeout is expected from the recorded environment and is not evidence that
the final report failed. The baseline is a representative proxy, not
Adwoa's original query, so the recorded timings are not an exact
apples-to-apples speedup. See [explain_before.md](evidence/explain_before.md)
and [reporting_after.md](evidence/reporting_after.md).

### Deliberately unsafe race demonstration

The optional `scripts/run_baseline_race.ps1` demonstrates a check-then-update
race in a separate schema and removes that schema afterwards. **The script
currently targets the database named `kloudkart`, not `$DbName`.** It only
creates and drops the `kloudkart_baseline_race` fixture schema, but run it
only against a local database you are comfortable using for a test:

```powershell
.\scripts\run_baseline_race.ps1
```

The expected demonstration is two successful attempts for one unit and a
final stock of `-1`. This is intentionally broken example code; never use it
to place real orders. The passing production-path test is the supplied
`data/race_test.py` described above.

## Decisions and known limitations

- **Status meaning:** `completed`, `complete`, and `shipped` count as spending;
  pending, cancelled, and refunded do not. Confirm this with the business.
- **Spending amount:** the report uses `orders.total_amount`. There are
  2,426 order/line total differences, so neither amount is proven correct.
- **Reporting date:** `2026-08-31` is the supplied extract's assumed cutoff.
  Later records are flagged for review when that date is passed.
- **Low-stock threshold:** 10 units is a configurable default because the
  brief does not set a cutoff.
- **Historical stock:** negative stock and legacy orphan records are
  preserved, not silently corrected. The inventory log does not provide a
  confirmed opening balance, so the 144 stock/log differences are unverified.
- **Movement logging:** `place_order` logs its sales atomically. The current
  solution does not automatically log every direct stock update, restock, or
  correction. A production rollout needs a controlled, logged path for all
  stock changes.
- **Application integration:** the repository contains the database
  function, not the checkout application. The application must call
  `place_order`; otherwise the race protection is not in effect.
- **Performance comparison:** the supplied brief did not include Adwoa's
  original query. The baseline is a proxy that timed out, so do not claim an
  exact before/after speedup.

For the full findings, assumptions, and recommendations, see
[the diagnosis](docs/01_data_diagnosis.md),
[key decisions](docs/02_key_decisions.md),
[the memo to Nana](docs/03_memo_to_nana.md), and the [ADR records](decisions/).

## Troubleshooting

### Docker reports that port 5432 is already in use

Change the host side of the port mapping in `docker-compose.yml` from
`5432:5432` to `5433:5432`, then recreate the container with
`docker compose up -d db`. The host connection string for the race test must
then use port `5433`. The `docker exec` commands in this README continue to
work because they connect inside the container.

### `createdb` says the database already exists

Choose a new disposable name and assign it to `$DbName`. Do not point the
runner at an existing database just to avoid creating a test database;
`run_all.sql` reloads the source tables.

### The runner cannot find a CSV file

Confirm the CSVs are directly inside `data/`, alongside `load.sql`. The
source bundle is mounted read-only at `/data`; `run_all.sql` sets the
container-side working directory so the supplied relative `\copy` paths
resolve.

### The race test cannot connect or reports too many connections

Check `docker compose ps`, `docker exec kloudkart-db pg_isready -U postgres`,
the host port in `DATABASE_URL`, and `max_connections`. The race test needs
400 simultaneous connections plus room for PostgreSQL and administrative
connections.

### The Python test says `psycopg2 is not installed`

Install the requirements into the project environment and run its Python:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe data\race_test.py
```

## Cleanup

After confirming `$DbName` is the disposable lab database, remove only that
database:

```powershell
docker exec kloudkart-db dropdb -U postgres $DbName
```

Stop the service without deleting its persistent volume:

```powershell
docker compose stop db
```

Avoid `docker compose down -v` unless you deliberately want to delete the
PostgreSQL data volume as well.
