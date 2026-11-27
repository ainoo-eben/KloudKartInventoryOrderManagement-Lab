# ADR-009: Raise max_connections to 500 for the flash-sale test; pool connections in production

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Lab participant

## Context

`race_test.py` Test 2 opens **400 simultaneous connections**, one per buyer, and must pass "run exactly as shipped". PostgreSQL's default `max_connections` is **100**. With the default, the 101st buyer onwards gets `FATAL: sorry, too many clients already`. The test counts that as an unhandled error, so it fails before `place_order`'s locking is even exercised. The first recorded pass was achieved by raising the limit by hand (`ALTER SYSTEM`, restart, restore). A fresh container would have failed.

This is not just a test artefact. Marketing expects ~400 orders in 10 seconds on flash-sale day. If the checkout application opens one database connection per shopper, the same wall appears in production, and those shoppers see an error page instead of "out of stock".

## Decision

1. **Lab / grading environment:** `docker-compose.yml` starts PostgreSQL with `max_connections=500`. That covers 400 test buyers plus headroom for psql, admin and the test's own fixture connections. It is a configuration flag on the existing server: no new infrastructure and no cost.
2. **Production recommendation:** the checkout application should use a **connection pool** of roughly 20–50 connections (built into most web frameworks' database drivers). The 400 shoppers then queue for a connection inside the application for a few milliseconds each, instead of each holding a server connection. Raise `max_connections` on the real server only as far as its memory allows.

## Alternatives considered

### Alternative A: Leave the default and document the requirement
- **Why rejected:** A grader or teammate running the project as documented would see Test 2 fail with "too many clients" and reasonably conclude the overselling fix is broken. The requirement belongs in configuration, not in a paragraph.

### Alternative B: Add PgBouncer (an external connection pooler) in front of PostgreSQL
- **Why attractive:** The standard production answer; the server sees few connections however many clients connect.
- **Why rejected here:** It is a new piece of infrastructure to run and monitor, which the brief rules out ("no new databases, infrastructure"). An in-application pool gets the same benefit with nothing new to operate.

### Alternative C: Make place_order queue requests itself (advisory locks, a queue table)
- **Why rejected:** The bottleneck is connection *admission*, which happens before any SQL runs. Nothing inside the function can help a connection that was refused.

## Consequences

- **What this buys:** The supplied test passes on a fresh `docker compose up`, with no manual steps. Verified: `SHOW max_connections` returns 500 and race_test.py passes unmodified (see [race_test_runs.md](../evidence/race_test_runs.md)).
- **What this costs:** Each idle PostgreSQL connection reserves a few MB of memory. 500 is fine on a laptop or a modest server, but it is not free, so production should pool rather than simply raise the number.
- **What it costs Nana if I'm wrong:** If checkout opens one connection per shopper and nobody adds a pool, flash-sale buyers beyond the server's limit get errors. That is lost sales and a bad first flash sale, even though no stock is oversold.
- **What would make me revisit this:** Production traffic numbers from checkout: how many concurrent connections the application actually opens at peak.
