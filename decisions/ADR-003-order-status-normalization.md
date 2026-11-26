# ADR-003: Order status normalization for spending report

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The `orders.status` column is free text with 15 distinct values, including inconsistent capitalization: `completed`, `COMPLETED`, `Completed`, `complete`, `shipped`, `refunded`, `CANCELLED`. The spending report must decide which orders count as revenue. The extract cannot prove whether shipped orders were paid or whether refunds can be partial.

## Decision

Compare `lower(trim(status))` and map observed labels as follows:

| Normalized value | Report category | Counts as spending? |
|---|---|---|
| `completed`, `complete` | completed | Yes |
| `shipped` | shipped | Yes |
| `pending` | pending | No |
| `cancelled`, `canceled` | cancelled | No |
| `refunded` | refunded | No |

Pending, cancelled, and refunded orders are excluded. The mapping is kept explicit in the report query (not hidden in a view) so anyone can see and adjust it. Do not merge customer records based on email — use `customer_id` as the report identity.

## Alternatives considered

### Alternative A: Exact string match on status

- **How it would work:** Filter `WHERE status = 'completed'` only.
- **Why it is attractive:** Simple; no normalization logic.
- **Why rejected:** Misses `COMPLETED`, `Completed`, `complete` — silently excludes valid orders. The data has 15 variants; exact matching loses revenue.

### Alternative B: Create a status lookup table with FK

- **How it would work:** Add a `status_codes` table, FK from `orders.status` to it, normalize legacy values via migration.
- **Why it is attractive:** Clean, enforced, queryable.
- **Why rejected:** Requires rewriting historical statuses, which violates the decision to preserve legacy rows. Also adds schema complexity for a reporting concern that belongs in the report query, not the transactional schema.

### Alternative C: Add a check constraint on status

- **How it would work:** `ALTER TABLE orders ADD CONSTRAINT valid_status CHECK (status IN ('completed', 'shipped', ...))`.
- **Why it is attractive:** Prevents future invalid values.
- **Why rejected:** Would fail on the existing 15 variants — the constraint can't be added without first rewriting all historical statuses. Use `NOT VALID` (see ADR-006) for new writes only, and normalize in the report for now.

## Consequences

- **What this buys:** Consistent revenue calculation despite messy status data. The mapping is transparent and adjustable.
- **What this costs:** If shipped orders were never paid, revenue is overstated. If refunds can be partial, the full order amount is excluded instead of the refund amount.
- **What it costs the client if I am wrong:** Customer totals misstated by the proportion of shipped-but-unpaid or partially-refunded orders. Mitigation: the mapping is explicit in the report and can be changed without schema changes.
- **What would make me revisit this:** Payment records or delivery confirmations become available, allowing a more precise revenue definition.

## What this survives

The report produces consistent, defensible numbers from messy data. The normalization logic is visible and adjustable without touching the schema.<|end|>