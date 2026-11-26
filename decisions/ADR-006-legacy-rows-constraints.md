# ADR-006: Legacy rows and constraints — NOT VALID approach

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The existing data has orphaned references: missing customers on orders (210), missing orders on order_items (692), missing products on inventory_log (120), and broken category references (1 category with missing parent). There are also 299 duplicate email groups, 14 negative stock quantities, 37 products without categories, and 3 unreachable categories. Adding strict foreign keys or unique constraints would fail on this data. The brief says schema changes are fine if documented, and Nana's team lives with them after we leave.

## Decision

Preserve the supplied records and avoid guessed repairs. Add appropriate foreign keys as `NOT VALID` where legacy rows violate them, so new writes are checked while old exceptions remain visible. Validate them only after a documented cleanup.

- Do not add a unique email constraint while normalized duplicate groups remain.
- For future rows, require positive order quantities and non-NULL, non-negative receipt prices.
- Allow zero prices (possible gifts); no negative line prices were found.
- Keep status normalization in the report (ADR-003); do not silently rewrite historical statuses.
- Add a non-validating `stock_quantity >= 0` check so existing negative-stock rows remain loadable while new writes cannot create negative stock (see ADR-002).

## Alternatives considered

### Alternative A: Validate all constraints immediately (VALID)

- **How it would work:** Add FKs and check constraints with full validation on the existing data.
- **Why it is attractive:** Clean, enforced from day one.
- **Why rejected:** Would fail — 210 orders reference missing customers, 692 order_items reference missing orders, etc. Can't add constraints without first fixing or deleting legacy data, which we won't do (ADR-002).

### Alternative B: Fix legacy data first, then add constraints

- **How it would work:** Delete or repair orphaned rows, then add strict constraints.
- **Why it is attractive:** Results in a clean schema with full enforcement.
- **Why rejected:** Requires guessing (which customer did order 540830 belong to?) or deleting data, which loses audit-trail evidence. The brief says "not everything that looks wrong is wrong" — some orphans may be intentional or historical.

### Alternative C: No constraints at all (app-level enforcement)

- **How it would work:** Keep the schema as-is; enforce integrity in application code only.
- **Why it is attractive:** No migration risk; works with existing data.
- **Why rejected:** This is what exists today, and it's why the data is broken. The diagnosis found 692 orphaned order_items, 210 orphaned orders, etc. App-level enforcement didn't work.

## Consequences

- **What this buys:** New writes are protected immediately. Legacy exceptions are visible and documented. The schema improves without breaking existing data.
- **What this costs:** Some old data remains inconsistent. Nana's team must clean it up before validating constraints.
- **What it costs the client if I am wrong:** If a legacy orphan is actually a data-entry error that should have been caught, it persists. Mitigation: the data-quality exceptions report (ADR-008) surfaces all known exceptions.
- **What would make me revisit this:** Nana's team completes the cleanup and runs `ALTER TABLE ... VALIDATE CONSTRAINT`.

## What this survives

The schema improves incrementally without data loss. New writes are safe. Legacy problems are visible and tracked, not hidden.<|end|>