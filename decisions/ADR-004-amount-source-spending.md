# ADR-004: Amount source for customer spending — orders.total_amount

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

There are 2,426 orders where `orders.total_amount` does not equal the sum of `order_items.quantity * order_items.unit_price`. There are also 148 receipt lines with NULL prices and no common numeric difference explaining the mismatches. The spending report needs a single amount to aggregate per customer. The schema describes `total_amount` as "written by the application at checkout," so it may include order-level fees or discounts absent from receipt lines.

## Decision

Use `orders.total_amount` as the best available checkout amount, applying the status rule from ADR-003. This is a provisional source-of-truth choice, not a claim that every stored total is correct.

- Do not overwrite either amount from the other (neither `orders.total_amount` nor computed line-item sums).
- Expose the mismatch count (2,426) as a data-quality warning in the report.
- Preserve existing NULL prices and flag them rather than filling with today's product price (which may have changed).
- Allow zero-priced receipt lines as possible free gifts; no negative line prices were found.
- Revisit this choice if checkout, delivery-fee, discount, or payment records become available.

## Alternatives considered

### Alternative A: Use computed line-item sums instead of total_amount

- **How it would work:** `SUM(order_items.quantity * order_items.unit_price)` per order, ignoring `orders.total_amount`.
- **Why it is attractive:** Line items are more granular; recomputing avoids trusting a stored value.
- **Why rejected:** Line items have 148 NULL prices and 2,426 mismatches. The computed sum is also wrong in many cases. Additionally, `total_amount` may include order-level fees/discounts that line items don't capture.

### Alternative B: Reconcile by overwriting one from the other

- **How it would work:** Update `orders.total_amount` to match line-item sums (or vice versa) for the 2,426 mismatches.
- **Why it is attractive:** Eliminates the discrepancy; one consistent number.
- **Why rejected:** We don't know which is correct. Overwriting destroys evidence. The brief says "not everything that looks wrong is wrong" — the mismatch may reflect legitimate fees/discounts.

### Alternative C: Average or blend both sources

- **How it would work:** Use `(total_amount + computed_sum) / 2` for mismatched orders.
- **Why it is attractive:** Reduces the impact of either being wrong.
- **Why rejected:** Produces a number that is definitely wrong in a new way. No business meaning.

## Consequences

- **What this buys:** A defensible, single source of truth for the report. The mismatch is visible, not hidden.
- **What this costs:** 2,426 orders (~1.5%) may have incorrect totals. Customer spend figures are approximate.
- **What it costs the client if I am wrong:** If `total_amount` is systematically wrong (e.g., always missing a delivery fee), all customer totals are off by that amount. Mitigation: the data-quality exceptions report (ADR-008) flags every mismatch.
- **What would make me revisit this:** Checkout records, delivery-fee data, or payment confirmations become available.

## What this survives

The report produces numbers that are traceable to a single, documented source. The uncertainty is quantified and visible, not buried.<|end|>