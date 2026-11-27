# Supplied Race Test Runs

- Test: `data/race_test.py`, unmodified, all four tests (SHA-256 `5F12A6697400DEE3876DFA33A03FBDCC1DC906F665F3C0A6AAEFFE73CDB27D00`)
- Server: PostgreSQL 16 from `docker-compose.yml` as shipped (`max_connections = 500`, [ADR-009](../decisions/ADR-009-connection-limit.md)); no manual configuration changes
- Database: fresh disposable load via `sql/run_all.sql`, including the stock-logging trigger (ADR-002)
- Runner: [scripts/validate_all.ps1](../scripts/validate_all.ps1), **3 consecutive runs**

| Run | Result | Test 1 (2 buyers, 1 unit, 25 rounds) | Test 2 (400 buyers, 50 units) | Test 3 (oversized order) | Test 4 (trail) |
|---|---|---|---|---|---|
| 1 | PASS | 25/25 one winner | 50 sold, 350 refused, 0 errors, 3.39 s | refused, stock untouched | 5 sold, 6 movements* |
| 2 | PASS | 25/25 | 50 / 350 / 0, 2.96 s | refused | 5 sold, 6 movements* |
| 3 | PASS | 25/25 | 50 / 350 / 0, 3.13 s | refused | 5 sold, 6 movements* |

\* 5 sales plus the fixture product's `opening_stock` movement, written by the safety-net trigger when the test inserts its product.

Full captured output of each run: [final_validation.md](final_validation.md).

## History

The previous validation run (same code, before the CSV pre-flight step was added) gave 2.49 s, 2.77 s and 2.82 s for Test 2. The spread between runs is normal laptop variation; every run is well inside marketing's 10-second window.

The first recorded pass (2026-11-26, before the stock-logging trigger) completed Test 2 in 2.65 s. It needed `max_connections` raised by hand from 100 to 450. With the PostgreSQL default of 100, Test 2 fails with "too many clients" before order placement is exercised. That requirement is now in `docker-compose.yml`.
