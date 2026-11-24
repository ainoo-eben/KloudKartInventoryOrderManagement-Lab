# Kloud Kart Inventory Order Management Lab

Kloud Kart Ltd., an e-commerce company in Accra, runs on a plain PostgreSQL server serving roughly 4,000 orders a day on a schema that was never redesigned. This lab addresses Nana Adjei's two critical problems:

1. **Overselling** — two orders raced for the last unit, both succeeded, and customers paid for stock that didn't exist.
2. **Slow Monday report** — Adwoa's weekly customer-spending report takes ~40 minutes and sometimes doesn't finish.

## Current setup

Folder structure:

```
KloudKartInventoryOrderManagement-Lab/
├── data/
├── docs/
├── evidence/
├── scripts/
├── sql/
├── .venv/              (Python virtual environment, not activated)
├── .gitignore
├── README.md
└── lab-brief.txt
```

Activate venv: `.\.venv\Scripts\Activate.ps1` (PowerShell) or `.\.venv\Scripts\activate.bat` (CMD)

## Deliverables (from lab brief)

- Written diagnosis of the data: every problem found, how detected, cost if uncorrected, ranked by danger.
- Working SQL solution: schema objects, procedures/functions, views, and reports running top-to-bottom against a fresh load satisfying Nana's four criteria (no overselling, fast report, low-stock visibility, full audit trail).
- Written explanation of key decisions: overselling solution, report performance, assumptions made.
- One-page memo to Nana: business-language summary of what was built/found, recommendations, and what can't be personally stood behind.
- One improvement beyond the brief, implemented and justified.

## Constraints

- Existing PostgreSQL server only; no new databases, infrastructure, or monthly bill.
- Schema changes fine if documented.
- Order-placement mechanism tested with `race_test.py`; must pass unmodified.
- Don't hard-code category tree depth.
- Build for flash-sale spikes (~400 orders in ten seconds on a single product).
