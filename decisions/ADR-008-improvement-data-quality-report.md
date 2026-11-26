# ADR-008: Improvement beyond the brief — data-quality exceptions report

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The brief requires one improvement beyond the brief, implemented and justified in terms of what it's worth to Nana or Adwoa. The data diagnosis found 13 distinct data-quality problems. Nana's team currently discovers data issues reactively (e.g., noticing overselling after the fact). There is no recurring mechanism to surface data-quality exceptions before they affect business decisions.

## Decision

Add a data-quality exceptions report that surfaces:
- Status variants (inconsistent capitalization, unknown values)
- Order/line total differences (mismatched `total_amount` vs computed sums)
- Missing prices (NULL in order_items.unit_price)
- Orphan references (order_items without orders, orders without customers, inventory_log without products)
- Suspect dates (future order_date, future inventory_log.created_at)
- Negative stock (products with stock_quantity < 0)
- Stock/log reconciliation (products where stock_quantity ≠ sum of inventory_log.change_qty)

Stock/log exceptions must remain marked **unverified** until a trusted opening-stock baseline is established. This report surfaces exceptions; it does not silently change business data.

## Alternatives considered

### Alternative A: Automated low-stock alerts

- **How it would work:** A trigger or scheduled job that sends notifications when product stock falls below a threshold.
- **Why it is attractive:** Directly helps Nana prevent stockouts.
- **Why rejected:** Requires notification infrastructure (email, Slack, etc.) that Nana doesn't have. The brief says "no new infrastructure, no monthly bill." Also, the core problem is overselling (concurrency), not stockout awareness.

### Alternative B: Stock reservation timeout (hold stock during checkout)

- **How it would work:** Reserve stock for X minutes when a cart is created; release if not purchased.
- **Why it is attractive:** Prevents overselling at the cart level, not just at order placement.
- **Why rejected:** Adds complexity (reservation table, cleanup job, timeout logic). The order-placement function (ADR-001) already prevents overselling at the critical moment. The added complexity isn't justified by the brief's scope.

### Alternative C: Customer deduplication tool

- **How it would work:** Merge customer records that share an email or phone number.
- **Why it is attractive:** Improves report accuracy.
- **Why rejected:** Merging customers is a business decision, not a technical one. The brief says "where this brief doesn't settle something, decide and tell him what you decided." Customer identity is a business rule we shouldn't impose. Flagging duplicates is safer than merging them.

## Consequences

- **What this buys:** Nana and Adwoa get a recurring, automated view of data-quality issues. Problems are caught early, not discovered in a weekly report.
- **What this costs:** One more report to maintain. It must be re-run periodically to stay current.
- **What it costs the client if I am wrong:** If the exceptions report has false positives, Nana's team wastes time investigating. Mitigation: each exception includes the detection query so it can be verified.
- **What would make me revisit this:** If Nana's team finds the report too noisy or not actionable, simplify the output or add severity thresholds.

## What this survives

The report is self-documenting — each exception includes the SQL that found it. It runs on existing PostgreSQL infrastructure with no new dependencies. It complements, rather than replaces, the core overselling and reporting fixes.