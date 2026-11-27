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
| Prevent overselling | `public.place_order(...)` uses a conditional stock update and writes the order, order item, and sale movement in the same transaction. Refusals say "out of stock", "product not found", or "no price set". | Supplied race test, unmodified, **3/3 consecutive passes**: 25/25 last-unit rounds; 400 buyers / 50 units → exactly 50 sold, 0 errors, ~3 s (2.5–3.7 s across recorded runs). [race_test_runs.md](evidence/race_test_runs.md) |
| Audit trail of every stock movement | `public.adjust_stock(...)` for restocks, returns, corrections, damage, and stock takes (reason + note, can't go below zero). A safety-net trigger logs any other stock change as `unlogged_direct_update`; new products get an `opening_stock` movement. | 33 self-checking assertions in `sql/06_validation/01_assertions.sql`, run by `run_all.sql`. [ADR-002](decisions/ADR-002-stock-movements-legacy.md) |
| Customer spending | `public.customer_spending_report(...)` returns every customer: lifetime total, order count, twelve zero-filled months each with 12-month and lifetime running totals, rank, and top-100 flag. | All 40,420 customers in **~3 s** (old-style report: **9.2 min**). [performance_before_after.md](evidence/performance_before_after.md) |
| Low-stock rollup | `public.low_stock_rollup(...)` recursively follows the category tree to any depth and guards against cycles. | ~4 ms; stays correct when a 5th level is added, where a fixed-depth join loses products. [performance_before_after.md](evidence/performance_before_after.md) |
| Data-quality review (improvement) | `public.data_quality_exceptions(...)` reports known exceptions, including stock changed outside the approved process, without modifying source data. | [data_quality_report.md](evidence/data_quality_report.md) |

**One-command check:** `.\scripts\validate_all.ps1` first pre-flights the six
CSVs, then loads a fresh disposable database, runs everything including the
assertions, runs the race test 3 times, times both reports, drops the
database, and writes [final_validation.md](evidence/final_validation.md).
Latest result: **PASS**.

The script is PowerShell and was tested on **Windows** (PowerShell 5.1). On
macOS/Linux, install PowerShell 7 and run `pwsh ./scripts/validate_all.ps1`.
It is written to be cross-platform (it finds `.venv/bin/python`), but that
has not been tested; the manual steps under
[Reproduce the complete solution](#reproduce-the-complete-solution) work on
any OS.

These are lab results, not a production deployment. The checkout application
must call `place_order`, and stock tools should call `adjust_stock`, for the
protections to apply. Changes that bypass them are still logged and flagged,
but not prevented.

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
|   |-- 03_ordering/             Atomic order placement and logged stock adjustments
|   |-- 04_reporting/            Customer and low-stock reports
|   |-- 05_improvement/          Data-quality exceptions report
|   |-- 06_validation/           Self-checking assertions (rolled back)
|   `-- run_all.sql              Fresh-load solution runner
|-- docs/                        Diagnosis, decisions, and memo
|-- decisions/                   Architecture decision records
|-- evidence/                    Captured test and performance results
|-- scripts/                     CSV pre-flight, validation, benchmark, baseline race
|-- docker-compose.yml           PostgreSQL 16.16 pinned by digest, max_connections=500
|-- .env.example                 Optional local password override (copy to .env)
|-- requirements.txt             Host-side Python test dependency (exact pin)
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

The Compose file starts PostgreSQL 16.16 (pinned by image digest, so reruns
use the exact image the recorded timings came from) with local lab
credentials (`postgres` / `postgres`). These credentials are for local testing
only, not for a public or production server. To use a different password,
copy `.env.example` to `.env` (ignored by Git) before the first
`docker compose up`; set the same `POSTGRES_PASSWORD` in your shell for
`validate_all.ps1`, and use it in the `DATABASE_URL` examples below.

## Reproduce the complete solution

Run these commands from the repository root in PowerShell.

### 1. Check that the input bundle is present

```powershell
Get-ChildItem .\data
```

You should see the two SQL files, `race_test.py`, and all six CSV files. If
they are missing, get the original bundle before continuing.

Then check the CSVs are safe to load (read-only, about 7 seconds):

```powershell
.\scripts\preflight_csv.ps1
```

`load.sql` maps CSV columns **by position** and skips the header without
reading it, so a re-exported file with reordered columns (for example `price`
and `stock_quantity` swapped) would load with no error and quietly corrupt
every report. The pre-flight fails if any header differs from the column order
`load.sql` expects, if any row has the wrong number of fields or a non-numeric
ID, or if a file has fewer than 90% of the supplied extract's rows (a truncated
export). Use `-DataDir` to check a new extract and `-MinRowRatio` to change the
90% floor.

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
docker exec kloudkart-db psql -X -U postgres -d $DbName -v ON_ERROR_STOP=1 -v confirm_reload=yes -f /sql/run_all.sql
if ($LASTEXITCODE -ne 0) {
    throw "The SQL runner failed. Read the PostgreSQL error above before continuing."
}
```

`-X` prevents a local `psql` startup file from changing the run, and
`ON_ERROR_STOP=1` stops at the first SQL error. `confirm_reload=yes` is your
confirmation that `$DbName` is disposable: without it the runner refuses to
start, and it always refuses the persistent `kloudkart` database. The runner
performs these steps in order:

1. Recreates the six source tables from `data/schema.sql`.
2. Loads the CSVs using the supplied `data/load.sql`.
3. Prints the baseline row counts and runs the nine read-only audit files.
4. Adds ID sequences, non-validating constraints, and indexes.
5. Installs `place_order`, `adjust_stock` and the stock-logging trigger, the
   two business reports, and the data-quality exceptions function.
6. Runs the self-checking assertions (in a transaction that is rolled back).

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
**3 seconds** on the validation machine (see
[performance_before_after.md](evidence/performance_before_after.md)). Timings vary with hardware.

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
was about **4 ms**.

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

The test opens 400 simultaneous connections. PostgreSQL's default limit is
100, so `docker-compose.yml` starts the server with `max_connections=500`
(see [ADR-009](decisions/ADR-009-connection-limit.md)). If you created the
container before this setting existed, recreate it with
`docker compose up -d db` (the `pgdata` volume is kept). Confirm the limit:

```powershell
docker exec kloudkart-db psql -X -U postgres -At -c "SHOW max_connections"   # expect 500
```

Run the test. The `DATABASE_URL` below embeds the local lab credentials
(`postgres:postgres`). Use it only for this disposable Docker database and
never copy it into a shared environment, script, or configuration file:

```powershell
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/$DbName"
.\.venv\Scripts\python.exe data\race_test.py
$RaceExit = $LASTEXITCODE
Remove-Item Env:DATABASE_URL
if ($RaceExit -ne 0) {
    throw "The supplied race test failed."
}
```

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

The latest recorded runs completed the 400-buyer case in **2.7–3.7 seconds**
with no errors. See [race_test_runs.md](evidence/race_test_runs.md) for the captured
output.

## Optional baseline experiments

These experiments demonstrate why the solution was needed. They are not part
of `run_all.sql`.

### Slow baseline report

`sql/00_baseline/02_naive_report.sql` uses `EXPLAIN ANALYZE`, which executes
the deliberately naive query. It may run for a long time. The like-for-like
version (every customer) measured **552 s (9.2 min)** on the supplied schema;
`scripts/benchmark.ps1 -FullNaiveBaseline` reproduces it together with the
index ablation and the depth-5 rollup demo. Run only on a disposable database:

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
race in a separate `kloudkart_baseline_race` schema and drops that schema
afterwards; it never touches the solution tables. The target database is a
required parameter, and the script stops if that database does not exist:

```powershell
.\scripts\run_baseline_race.ps1 -DbName $DbName
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
- **Movement logging:** every new stock change is logged (sales by
  `place_order`, other movements by `adjust_stock`, anything else by the
  safety-net trigger). The trigger records but does not *prevent* direct
  edits; revoking direct `UPDATE` on `products` is the recommended next step
  once Kloud Kart's database roles are known (ADR-002).
- **Application integration:** the repository contains the database
  function, not the checkout application. The application must call
  `place_order`; otherwise the race protection is not in effect. For flash
  sales it should also pool its database connections (ADR-009).
- **Input files:** the CSV pre-flight checks structure (column order, field
  counts, IDs, row counts), not meaning. A new extract with the right shape
  but new problems (another status spelling, more orphans) loads normally;
  those are surfaced by the audits and the data-quality exceptions report.
- **Performance comparison:** Adwoa's original query was not supplied. The
  stand-in old-style report (9.2 min) and the new report (~3 s) are measured
  like-for-like on the same laptop, but no multiplier against her "40 minutes"
  is claimed. The missing index was the main cause of the slowness; see
  [performance_before_after.md](evidence/performance_before_after.md).

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
