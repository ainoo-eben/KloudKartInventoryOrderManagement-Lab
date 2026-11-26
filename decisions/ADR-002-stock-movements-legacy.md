# ADR-002: Stock movements logged in-transaction; legacy stock not rewritten

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The current extract has 14 products with negative stock and 144 products whose current stock differs from the sum of logged changes. The inventory_log does not establish a trusted opening-stock baseline — it only records movements, not starting inventory. Every new order must produce a trail of every stock movement, sale, restock, and correction that an auditor can walk through.

## Decision

Every new order writes one negative `sale` movement in `inventory_log` in the same transaction as the stock decrement and order records. Existing history is not rewritten or "balanced" by guessed adjustments.

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
- **Why rejected:** Two audit tables create confusion about which is authoritative. Better to fix the existing `inventory_log` to be reliable going forward and clearly mark legacy rows as unverified.

## Consequences

- **What this buys:** A complete, trustworthy audit trail for all new stock movements. Legacy problems are flagged, not hidden.
- **What this costs:** 14 negative-stock products and 144 mismatches remain unresolved until Nana's team provides a baseline.
- **What it costs the client if I am wrong:** If the 144 mismatches include real unlogged stock movements, Nana's inventory is further off than reported. Mitigation: the data-quality exceptions report (ADR-008) surfaces these.
- **What would make me revisit this:** If Nana's team provides a trusted opening-stock count, we can reconcile the 144 mismatches and validate the check constraint.

## What this survives

New stock movements are fully auditable. Legacy data remains visible and flagged, not silently corrected. The system works correctly going forward even with dirty historical data.