#!/usr/bin/env bash
# Verify the whole Pune Cinemas data layer against real PostgreSQL + Redis.
# Proves: the schema loads, a booking is atomic, DOUBLE-BOOKING IS IMPOSSIBLE
# (both sequentially and under true concurrency), the reads are correct, and
# the Redis holds / cache / rate-limiter behave as the capstone claims.
#
# Requires docker compose. Run:  ./scripts/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Run psql / redis-cli inside the compose containers, so no host clients are
# needed. -T disables TTY so we can pipe.
pg()  { docker compose exec -T db psql -U cinema -d cinema -v ON_ERROR_STOP=1 -qAt "$@"; }
pgf() { docker compose exec -T db psql -U cinema -d cinema "$@"; } # formatted, for humans
rc()  { docker compose exec -T cache redis-cli "$@"; }

pass=0; fail=0
check() { # check "label" "actual" "expected"
  if [ "$2" = "$3" ]; then echo "  PASS: $1"; pass=$((pass+1));
  else echo "  FAIL: $1 (got '$2', expected '$3')"; fail=$((fail+1)); fi
}

echo "== Starting PostgreSQL + Redis =="
docker compose up -d >/dev/null
# wait for health
for i in $(seq 1 30); do
  [ "$(docker compose ps db --format '{{.Health}}' 2>/dev/null)" = "healthy" ] &&
  [ "$(docker compose ps cache --format '{{.Health}}' 2>/dev/null)" = "healthy" ] && break
  sleep 2
done

echo "== Loading schema + seed (fresh) =="
pg -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' >/dev/null
pg -f /dev/stdin < sql/schema.sql >/dev/null
pg -f /dev/stdin < sql/seed.sql >/dev/null

echo "== Seed counts =="
check "movies"    "$(pg -c 'SELECT count(*) FROM movies;')"    "5"
check "seats"     "$(pg -c 'SELECT count(*) FROM seats;')"     "330"
check "shows"     "$(pg -c 'SELECT count(*) FROM shows;')"     "5"
check "customers" "$(pg -c 'SELECT count(*) FROM customers;')" "4"

echo "== Booking (atomic): customer 1 books A2, A3 for show 1 =="
pg -f /dev/stdin < sql/book.sql >/dev/null
check "booking amount_paise (2 x 25000)" "$(pg -c 'SELECT amount_paise FROM bookings WHERE id=1;')" "50000"
check "seats claimed for booking 1" \
  "$(pg -c "SELECT string_agg(s.row_label||s.seat_num, ',' ORDER BY s.seat_num) FROM booking_seats bs JOIN seats s ON s.id=bs.seat_id WHERE bs.booking_id=1;")" \
  "A2,A3"

echo "== Double-booking is refused (customer 2 tries A3, A4 for show 1) =="
set +e
ERR=$(docker compose exec -T db psql -U cinema -d cinema -v ON_ERROR_STOP=1 2>&1 <<'SQL'
BEGIN;
WITH chosen AS (
  SELECT s.id AS seat_id FROM seats s
  WHERE s.screen_id = (SELECT screen_id FROM shows WHERE id = 1)
    AND (s.row_label, s.seat_num) IN (('A',3), ('A',4))
),
new_booking AS (
  INSERT INTO bookings (show_id, customer_id, amount_paise)
  SELECT 1, 2, (SELECT count(*) FROM chosen) * (SELECT price_paise FROM shows WHERE id=1)
  RETURNING id
)
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT (SELECT id FROM new_booking), 1, seat_id FROM chosen;
COMMIT;
SQL
)
set -e
echo "$ERR" | grep -q "duplicate key value violates unique constraint" \
  && { echo "  PASS: second booking rejected with duplicate key"; pass=$((pass+1)); } \
  || { echo "  FAIL: expected a duplicate-key error, got: $ERR"; fail=$((fail+1)); }
# and the WHOLE transaction rolled back: A4 must still be free, no booking 2
check "no second booking row created" "$(pg -c 'SELECT count(*) FROM bookings;')" "1"
check "seat A4 still free (not half-booked)" \
  "$(pg -c "SELECT count(*) FROM booking_seats bs JOIN seats s ON s.id=bs.seat_id WHERE bs.show_id=1 AND s.row_label='A' AND s.seat_num=4;")" \
  "0"

echo "== True concurrency: two transactions race for seat B5 on show 2 =="
race() { # $1 = customer id; returns 0 if its booking committed
  docker compose exec -T db psql -U cinema -d cinema -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
BEGIN;
WITH chosen AS (
  SELECT s.id AS seat_id FROM seats s
  WHERE s.screen_id=(SELECT screen_id FROM shows WHERE id=2) AND (s.row_label,s.seat_num)=('B',5)
), nb AS (
  INSERT INTO bookings (show_id, customer_id, amount_paise)
  SELECT 2, $1, (SELECT price_paise FROM shows WHERE id=2) RETURNING id
)
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT (SELECT id FROM nb), 2, seat_id FROM chosen;
SELECT pg_sleep(0.3);
COMMIT;
SQL
}
race 3 & p1=$!
race 4 & p2=$!
r1=0; r2=0; wait $p1 || r1=$?; wait $p2 || r2=$?
winners=$(( (r1==0?1:0) + (r2==0?1:0) ))
check "exactly one concurrent booking for B5 won" "$winners" "1"
check "seat B5 booked exactly once (show 2)" \
  "$(pg -c "SELECT count(*) FROM booking_seats bs JOIN seats s ON s.id=bs.seat_id WHERE bs.show_id=2 AND s.row_label='B' AND s.seat_num=5;")" \
  "1"

echo "== Reads =="
check "availability for show 1 (100 - 2 booked)" \
  "$(pg -c 'SELECT sc.total_seats - count(bs.seat_id) FROM shows sh JOIN screens sc ON sc.id=sh.screen_id LEFT JOIN booking_seats bs ON bs.show_id=sh.id WHERE sh.id=1 GROUP BY sc.total_seats;')" \
  "98"
check "empty show 2 still returns a row (LEFT JOIN), available=80" \
  "$(pg -c 'SELECT sc.total_seats - count(bs.seat_id) FROM shows sh JOIN screens sc ON sc.id=sh.screen_id LEFT JOIN booking_seats bs ON bs.show_id=sh.id WHERE sh.id=3 GROUP BY sc.total_seats;')" \
  "80"
check "full-text search 'ladies' finds Laapataa Ladies" \
  "$(pg -c "SELECT title FROM movies WHERE to_tsvector('english',title) @@ plainto_tsquery('english','ladies');")" \
  "Laapataa Ladies"
check "revenue for Laapataa Ladies (confirmed): 500.00" \
  "$(pg -c "SELECT round(sum(b.amount_paise)/100.0,2) FROM bookings b JOIN shows sh ON sh.id=b.show_id JOIN movies m ON m.id=sh.movie_id WHERE b.status='confirmed' AND m.title='Laapataa Ladies';")" \
  "500.00"
echo "  (showtime listing, for the eye:)"
pgf -c "SELECT m.title, sc.name AS screen, sh.starts_at, round(sh.price_paise/100.0,2) AS price_rupees, sc.total_seats - count(bs.seat_id) AS seats_left FROM shows sh JOIN movies m ON m.id=sh.movie_id JOIN screens sc ON sc.id=sh.screen_id LEFT JOIN booking_seats bs ON bs.show_id=sh.id GROUP BY m.title, sc.name, sc.total_seats, sh.starts_at, sh.price_paise ORDER BY sh.starts_at;"

echo "== Redis: seat hold (SET NX EX) — race-free, self-expiring =="
rc FLUSHALL >/dev/null
check "customer 2 holds A5 (NX)"     "$(rc SET hold:show:1:seat:A5 customer:2 NX EX 120)" "OK"
check "hold TTL is set (~120)"       "$(rc TTL hold:show:1:seat:A5)"                        "120"
check "customer 3 REFUSED (NX, held)" "$(rc SET hold:show:1:seat:A5 customer:3 NX EX 120)" ""
rc SET hold:show:1:seat:A6 customer:2 NX EX 1 >/dev/null
sleep 1.3
check "hold A6 expired on its own"   "$(rc EXISTS hold:show:1:seat:A6)"                     "0"

echo "== Redis: availability cache (cache-aside + delete-on-write) =="
rc SET avail:show:1 98 EX 30 >/dev/null
check "cache hit returns 98"         "$(rc GET avail:show:1)"                               "98"
rc DEL avail:show:1 >/dev/null
check "cache miss after invalidation" "$(rc EXISTS avail:show:1)"                           "0"

echo "== Redis: rate limiter (atomic Lua INCR+EXPIRE) =="
rc DEL rl:book:customer:2 >/dev/null
LUA=$(cat redis/rate_limit.lua)
c1=$(rc EVAL "$LUA" 1 rl:book:customer:2 60)
for _ in 2 3 4 5; do last=$(rc EVAL "$LUA" 1 rl:book:customer:2 60); done
sixth=$(rc EVAL "$LUA" 1 rl:book:customer:2 60)
check "first attempt counts 1"       "$c1"    "1"
check "sixth attempt counts 6 (>5 limit -> reject)" "$sixth" "6"
check "counter key has an expiry set" "$([ "$(rc TTL rl:book:customer:2)" -gt 0 ] && echo yes || echo no)" "yes"

echo
echo "==================== RESULT: $pass passed, $fail failed ===================="
[ "$fail" -eq 0 ]
