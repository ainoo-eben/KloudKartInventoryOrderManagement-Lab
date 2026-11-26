# A note for Nana

**Subject: Safer orders and clearer stock and sales reports**

I reviewed the sample inventory and order records and built a safer order
process, updated reports, and a report that flags data issues for follow-up.

The main risk was that two customers could buy the same last item at nearly
the same time. The new order process checks and reduces stock as one protected
step, and records the order, its items, and the stock movement together. The
provided race test passed: when 400 buyers competed for 50 available units, 50
orders succeeded and 350 were correctly refused. The checkout application
must use this new process for the protection to apply.

The customer spending report now completed in about 3.85 seconds on the sample
data and returns all customers, monthly totals, and the top 100 ranking. The
older-style comparison query did not finish within two minutes. It was a
stand-in, not the original Monday report, so these results do not prove an
exact speedup against Adwoa's report.

The stock report can show products at or below 10 units by category; the cutoff
can be changed. A separate data-quality report lists unusual statuses, totals
that do not match receipt lines, missing prices or links, dates beyond the
chosen cutoff, and stock records that need review. It reports issues but does
not change them.

Some old records cannot safely be corrected from this extract alone. In
particular, stock movements do not establish each product's starting balance,
so a difference between current stock and logged movements is unverified.
Please confirm the starting stock, unusual order statuses, and the intended
report cutoff before treating those records as corrected business facts. The
report also relies on the recorded order total and treats completed, complete,
and shipped orders as spending.

The new SQL has been tested on a separate fresh-load database. The existing
database was not changed.
