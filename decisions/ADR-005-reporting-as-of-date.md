# ADR-005: Reporting as-of date for the supplied extract

- **Status:** Accepted
- **Date:** 2026-11-26
- **Decision owner:** Lab participant

## Context

The orders table spans Aug 2025 to Aug 2027. Orders grow steadily from ~2,000/month (Aug 2025) to a peak of ~36,000/month (Aug 2026), then drop to near-zero. There are **24 orders dated after the 2026-08-31 cutoff** (plus 40 inventory-log rows): 9 dated between 1 September and 27 November 2026, and 15 dated after today (December 2026 through August 2027), i.e. genuinely in the future. These are the figures in [the diagnosis](../docs/01_data_diagnosis.md), finding 8. The peak month (Aug 2026) has 36,357 orders; every subsequent month has 5 or fewer. The "live" data effectively ends in Aug 2026.

## Decision

For this supplied extract, use **2026-08-31** as the reporting as-of date and flag orders dated Sep 1, 2026 or later. August contains 36,357 orders; later-dated rows are suspect relative to the apparent extract boundary.

Make the as-of date an explicit report parameter. Do not permanently hard-code August 2026 into an operational report; use a later date only after the later records are verified. This avoids silently including questionable future-dated rows in this dataset's report.

## Alternatives considered

### Alternative A: Use the current date (now()) as the as-of date

- **How it would work:** Filter `order_date <= now()` and include all rows up to today.
- **Why it is attractive:** No manual cutoff; adapts automatically.
- **Why rejected:** `now()` in the container is Nov 2026, which would include the 9 suspect post-cutoff orders dated before today, and would start including the 15 future-dated ones as their dates pass. The data has an artificial boundary at Aug 2026; using `now()` silently includes questionable data.

### Alternative B: Hard-code Aug 2026 permanently

- **How it would work:** `WHERE order_date <= '2026-08-31'` baked into the report view.
- **Why it is attractive:** Simple; no parameter needed.
- **Why rejected:** The brief says "where this brief doesn't settle something, decide and tell him what you decided and why." Hard-coding a date is a decision, but it should be visible and adjustable, not buried in SQL. Making it a parameter keeps it transparent.

### Alternative C: Exclude future orders only (order_date <= now())

- **How it would work:** `WHERE order_date <= now()` — excludes only the 15 rows dated after today.
- **Why it is attractive:** Minimal change; keeps the most data.
- **Why rejected:** The drop from 36K to 5 orders/month after Aug 2026 is a data-quality signal, not just 15 bad rows. The future-dated orders are the tip of the iceberg; the entire post-Aug 2026 period (24 orders, GHS 68,040.02) is suspect.

## Consequences

- **What this buys:** A clean, defensible reporting window that excludes suspect data.
- **What this costs:** 24 orders (GHS 68,040.02) and 40 inventory-log rows dated after the cutoff are excluded from the report until verified.
- **What it costs the client if I am wrong:** If the post-Aug 2026 orders are actually legitimate (e.g., pre-orders), the report understates recent spend. Mitigation: flagged, not deleted; can be included later.
- **What would make me revisit this:** Nana's team confirms the post-Aug 2026 orders are real.

## What this survives

The report is reproducible and auditable. The cutoff is a parameter, not a hidden constant. Future data can be included once verified.