# ADR-002: Stock movements logged in-transaction; legacy stock not rewritten

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The current extract has 14 products with negative stock and 144 products whose current stock differs from the sum of logged changes. The inventory_log does not establish a trusted opening-stock baseline — it only records movements, not starting inventory. Every new order must produce a trail of every stock movement, sale, restock, and correction that an auditor can walk through.

## Decision

Every **new** stock change leaves an `inventory_log` row, written in the same transaction as the change, through one of three paths ([`02_stock_movements.sql`](../sql/03_ordering/02_stock_movements.sql)):

| Path | Used for | Reason recorded | Can refuse? |
|---|---|---|---|
| `place_order(...)` | Sales | `sale`, note = order number | Yes: "out of stock" |
| `adjust_stock(product, change, reason, note)` | Restock, return, correction, damage, stock take | The reason given; a note is required for corrections and stock takes | Yes: invalid reason, wrong sign, or a change that would go below zero |
| Safety-net trigger on `products` | Anything else: manual `UPDATE`, old scripts, back-office tools | `unlogged_direct_update`, note = database user and application | No (it records, it doesn't block) |

A new product inserted with stock also gets an `opening_stock` movement. That gives every product created from now on a starting point, so its stock always equals the sum of its log, which is exactly what the legacy data lacks.

The two functions set a transaction-local flag (`kloudkart.movement_logged`) only around their own `UPDATE`, so the trigger never double-logs their movement. The flag is cleared immediately afterwards, so a later direct update in the same transaction is still caught. `data_quality_exceptions()` lists every `unlogged_direct_update` row, so someone has to supply the missing reason.

Existing history is not rewritten or "balanced" by guessed adjustments.

- Do not set negative quantities to zero or manufacture opening movements.
- Treat the 144 stock/log mismatches as unresolved until a trusted opening count or baseline is supplied.
- Add a non-validating `stock_quantity >= 0` check so existing rows remain loadable while new writes cannot create negative stock; validate it after legacy negatives are reconciled.
- Keep the order function's conditional stock check, so a product with negative or insufficient stock cannot be sold.
- For new order, item, and log IDs, add sequences initialized above the current maximum IDs. Do not allocate IDs using `max(id) + 1`, which can collide under concurrent orders.

## Alternatives considered

### Alternative A: Rewrite legacy stock to zero and manufacture opening movements

- **How it would work:** Set all negative stock to 0, create opening-balance inventory_log entries to reconcile the 144 mismatches.
- **Why it is attractive:** Clean slate; stock counts would match log sums after the fix.
- **Why rejected:** The opening-stock baseline is unknown. Manufacturing movements creates a false audit trail — an auditor would see fictional restocks. The brief says "not everything that looks wrong is wrong"; guessing is worse than flagging.

### Alternative B: Event sourcing (append-only inventory_log as source of truth)

- **How it would work:** Rebuild `products.stock_quantity` from the sum of all inventory_log entries. Add a separate opening-balance event type.
- **Why it is attractive:** Single source of truth; audit trail is the data itself.
- **Why rejected:** Requires a trusted opening baseline that doesn't exist. Also requires schema redesign (event types, replay logic) that goes beyond the brief's scope and Nana's "no new infrastructure" constraint.

### Alternative C: Separate audit table with triggers

- **How it would work:** Keep `inventory_log` as-is (messy legacy data). Add a new `stock_audit` table populated by triggers on `products.stock_quantity` changes.
- **Why it is attractive:** Clean separation between legacy data and new audit trail.
- **Why rejected:** Two audit tables create confusion about which is authoritative. Better to make the existing `inventory_log` reliable going forward and clearly mark legacy rows as unverified.

### Alternative D: Trigger only (log every stock change from a trigger; no adjust_stock)

- **How it would work:** One AFTER UPDATE trigger writes every movement; staff keep updating stock directly.
- **Why it is attractive:** Nothing can bypass it; no new function for staff to learn.
- **Why rejected:** A trigger sees *that* stock changed, not *why*. An auditor needs to tell a restock from a theft write-off, and a trigger can only record "changed by user X". It also can't refuse a write-off that would take stock below zero with a clear message; it can only raise an error. So the trigger is the safety net, not the main path.

### Alternative E: Function only (adjust_stock, no trigger)

- **How it would work:** Ask everyone to use `adjust_stock`; rely on discipline.
- **Why it is attractive:** Simpler; every row has a real reason.
- **Why rejected:** This is exactly how the current gaps arose: 144 products whose stock no longer matches their log. One forgotten script or a manual fix in a database tool, and the trail is incomplete again, with nobody aware. The trigger makes a bypass *visible* instead of silent.

### Alternative F: Revoke direct UPDATE on products so the functions are the only way in

- **How it would work:** Application and staff roles get `EXECUTE` on the functions and no `UPDATE` on `products`.
- **Why it is attractive:** Prevention instead of detection.
- **Why rejected for now:** The lab has a single superuser and no knowledge of Kloud Kart's roles or of which tools write to `products`. Revoking blindly could break checkout. It is **recommended as the next step** once the team lists who writes stock; the trigger then becomes a pure backstop.

## Consequences

- **What this buys:** A complete audit trail for all new stock movements: sales, restocks, corrections, and even changes made outside the approved process. Legacy problems are flagged, not hidden.
- **What this costs:** 14 negative-stock products and 144 mismatches remain unresolved until Nana's team provides a baseline. One extra trigger check per stock update (measured: the 400-buyer race test still finishes in ~3.4 s). Staff must use `adjust_stock` to record a reason; direct edits still work but land on the exceptions report.
- **Verified by:** `sql/06_validation/01_assertions.sql` (sale logs exactly once; restock and correction log with sign and reason; a write-off below zero is refused; a raw UPDATE is caught; the flag doesn't leak) and race_test.py Test 4.
- **What it costs the client if I am wrong:** If the 144 mismatches include real unlogged stock movements, Nana's inventory is further off than reported. Mitigation: the data-quality exceptions report (ADR-008) surfaces these.
- **What would make me revisit this:** If Nana's team provides a trusted opening-stock count, we can reconcile the 144 mismatches and validate the check constraint.

## What this survives

New stock movements are fully auditable, including under flash-sale contention (race_test.py Test 4). Legacy data remains visible and flagged, not silently corrected. The system works correctly going forward even with dirty historical data.

**Limit:** the trigger records but does not prevent. A session that deliberately sets `kloudkart.movement_logged = 'on'` itself could hide a change. That requires knowing the internals, and it is closed by Alternative F (revoking direct UPDATE) when roles are set up.