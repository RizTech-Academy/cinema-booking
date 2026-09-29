# cinema-booking

**The reference project for the [RizTech Academy](https://www.riztechacademy.com/learn) Database Foundation
capstone** — the data layer of "Pune Cinemas", a cinema ticket-booking system, built on **two databases on
purpose** because that is what real systems do.

- **PostgreSQL** is the source of truth: movies, shows, screens, seats, bookings — with a `UNIQUE (show_id,
  seat_id)` constraint that makes **double-booking a seat impossible**, atomically, even under concurrency.
- **Redis** does the transient, fast, disposable work: **seat holds** during checkout (a key with a TTL that
  frees the seat automatically), an **availability cache** (cache-aside, invalidated on booking), and a
  **rate limiter** (an atomic Lua counter).

That split — durable/authoritative data in PostgreSQL, transient/derived data in Redis — is the polyglot
design the course argues for. If Redis vanished, the system would be slower but never *wrong*.

## Run and verify it

Everything is verified against real PostgreSQL 16 and Redis 7 with one command (needs Docker):

```bash
./scripts/verify.sh
```

It starts the two databases, loads the schema and seed, then proves the whole design — **24 checks**,
including that a second customer **cannot** book a taken seat (both sequentially and in a true concurrent
race), that the reads return the right numbers, and that the Redis holds, cache and rate limiter behave as
claimed.

To poke at it yourself:

```bash
docker compose up -d
docker compose exec db psql -U cinema -d cinema -f /path/to/sql/queries.sql   # or paste queries
docker compose exec cache redis-cli
docker compose down -v
```

## What's inside

| Path | What it is |
|------|-----------|
| `sql/schema.sql` | The PostgreSQL schema — every table, `CHECK`/`UNIQUE`/foreign-key constraint, indexes, and the full-text index. The `UNIQUE (show_id, seat_id)` on `booking_seats` is the line that defeats double-booking. |
| `sql/seed.sql` | Realistic data — 3 screens, 330 seats (generated with `generate_series`), 5 movies, 5 shows, 4 customers. |
| `sql/book.sql` | The booking as **one atomic transaction** (a CTE): create the booking and claim every seat together, with the amount computed in the database. |
| `sql/queries.sql` | The reads: availability (`LEFT JOIN`), free seats (`NOT EXISTS`), the showtime listing (no N+1), full-text search, revenue (`count(DISTINCT)`, confirmed only), occupancy. |
| `redis/rate_limit.lua` | The atomic `INCR`+`EXPIRE` rate limiter. |
| `scripts/verify.sh` | The full proof, run against real PostgreSQL + Redis. |
| `docker-compose.yml` | PostgreSQL 16 + Redis 7. |

## The one line that matters most

```sql
UNIQUE (show_id, seat_id)   -- on booking_seats
```

For any given show, each seat can be claimed **once**. A second attempt violates the constraint and the
database rejects it — not the application, the database, atomically. "Check if the seat is free, then book it"
in application code is a lost-update race; a database constraint closes that window for **every** code path.

## A note for learners

This is the finished capstone. Build it yourself by working through the five capstone lessons — design the
schema, prove the double-booking guarantee, write the queries, add the Redis tier — and compare with this repo
when you get stuck. Every file maps to a step in the course, and every choice is one you can defend from a
specific lesson.
