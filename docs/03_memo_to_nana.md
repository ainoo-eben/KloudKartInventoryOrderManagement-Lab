# A note for Nana

**Subject: Overselling fixed, Monday report in seconds, and what I found in the data**

**What I built.** Placing an order now checks and takes the stock in one step, so two customers can never get the same last unit. When 400 test shoppers rushed 50 units, exactly 50 bought and 350 were told "out of stock" at once, in about 3 seconds: well inside marketing's 10-second flash-sale estimate. Every stock change (sale, restock, correction, damaged goods) now leaves a record of what changed, when, and why. A change made outside the proper process is still recorded, with the login that made it, and flagged for follow-up. Adwoa's Monday report now covers every customer in about 3 seconds on an ordinary laptop, including the running totals she keeps by hand. The low-stock view by category is instant.

**Your two questions.**
- *Would "triggers" have fixed overselling?* No, not on their own. They can be written with the same flaw you have today. The fix is making "check stock" and "take stock" one step. I did use triggers for the stock records, which is the job they're good at.
- *Do you need the bigger server?* No. The report was slow mainly because the system had no quick way to find a customer's orders, so it re-read every order for every customer. On my laptop the old method takes about 9 minutes, and its time grows with every new customer; the new one takes about 3 seconds.

**What I found.** The biggest risks, in cedis:
1. Order statuses are typed in 15 different ways. A report that only looks for "completed" misses **GHS 314 million** of real sales, and one that ignores status counts **GHS 106 million** of cancelled, refunded or pending orders as sales.
2. **14 products** already show less than zero stock (**GHS 20,600** of goods sold that didn't exist).
3. For **144 products**, the stock count and the stock records disagree (up to **GHS 3.9 million**). I can't tell which is right without a physical count.
4. **1,068 customer accounts** share an email address with another, so some customers' spending (**GHS 9.7 million** in total) may be split across several accounts.

**What I recommend next.**
1. Make sure the checkout and any stock-editing tools use the new ordering and stock-adjustment steps. The protection only works if they do.
2. Before the first flash sale, have the checkout share a small, fixed number of connections to the stock system instead of one per shopper, and rehearse once at full volume.
3. Count the 144 mismatched products and the 14 negative ones, and record the counts properly.
4. Confirm what each order status means and whether "shipped" counts as a sale.
5. Then remove direct editing of stock levels, so the proper process is the only way in.

**What I can't stand behind yet.** The 144 stock differences are unverified until counted. Spending uses the order total recorded at checkout, which disagrees with the itemised lines on 2,426 orders. Orders dated after 31 August 2026 are held back as suspect. All timings come from my laptop, not your server.
