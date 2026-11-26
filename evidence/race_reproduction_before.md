# Baseline Oversell Reproduction

Ran two concurrent calls against an isolated fixture containing one unit. Both calls read the same available unit before either decremented stock.

| Attempt | Result |
|---:|---|
| 1 | success |
| 2 | success |

**Successful attempts:** 2  
**Starting stock:** 1  
**Final stock:** -1

This deliberately unsafe fixture demonstrates the race condition; it is not the final `place_order` function or the supplied `race_test.py`. The temporary schema was dropped after the run. The captured runner output is preserved below.

```text
BEGIN
DO
CREATE SCHEMA
CREATE TABLE
CREATE TABLE
INSERT 0 1
CREATE FUNCTION
COMMIT
success
success
successful_attempts|final_stock
2|-1
SET
DROP SCHEMA
```
