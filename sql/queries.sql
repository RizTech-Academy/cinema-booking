-- The reads the application needs, applying the query lessons to a real
-- workload. Each is one query, one round trip — no N+1.

-- 1. Seat availability for a show (the most-run query). LEFT JOIN so a show
--    with no bookings still returns a row (available = total).
SELECT sc.total_seats,
       count(bs.seat_id) AS booked,
       sc.total_seats - count(bs.seat_id) AS available
FROM shows sh
JOIN screens sc ON sc.id = sh.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = sh.id
WHERE sh.id = 1
GROUP BY sc.total_seats;

-- 2. Which specific seats are free (to draw the seat map). An anti-join with
--    NOT EXISTS (not NOT IN, which has the NULL trap).
SELECT s.row_label, s.seat_num
FROM seats s
WHERE s.screen_id = (SELECT screen_id FROM shows WHERE id = 1)
  AND NOT EXISTS (
    SELECT 1 FROM booking_seats bs WHERE bs.show_id = 1 AND bs.seat_id = s.id
  )
ORDER BY s.row_label, s.seat_num
LIMIT 5;

-- 3. The showtime listing (home page) — one query with joins + aggregate,
--    avoiding the N+1. total_seats must be in the GROUP BY.
SELECT m.title, sc.name AS screen, sh.starts_at,
       round(sh.price_paise / 100.0, 2) AS price_rupees,
       sc.total_seats - count(bs.seat_id) AS seats_left
FROM shows sh
JOIN movies m   ON m.id = sh.movie_id
JOIN screens sc ON sc.id = sh.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = sh.id
GROUP BY m.title, sc.name, sc.total_seats, sh.starts_at, sh.price_paise
ORDER BY sh.starts_at;

-- 4. Movie search — full-text (stems and ranks; scales with the GIN index),
--    not LIKE.
SELECT title FROM movies
WHERE to_tsvector('english', title) @@ plainto_tsquery('english', 'ladies');

-- 5. Revenue per movie — confirmed bookings only, count(DISTINCT) so the seat
--    fan-out does not inflate the booking count.
SELECT m.title,
       count(DISTINCT b.id) AS bookings,
       round(sum(b.amount_paise) / 100.0, 2) AS revenue_rupees
FROM bookings b
JOIN shows sh ON sh.id = b.show_id
JOIN movies m ON m.id = sh.movie_id
WHERE b.status = 'confirmed'
GROUP BY m.title
ORDER BY revenue_rupees DESC;

-- 6. Occupancy per show — LEFT JOIN so empty shows report 0%, and 100.0 * to
--    force decimal division.
SELECT m.title, sh.starts_at,
       count(bs.seat_id) AS sold,
       sc.total_seats,
       round(100.0 * count(bs.seat_id) / sc.total_seats, 1) AS percent_full
FROM shows sh
JOIN movies m   ON m.id = sh.movie_id
JOIN screens sc ON sc.id = sh.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = sh.id
GROUP BY m.title, sh.starts_at, sc.total_seats
ORDER BY percent_full DESC;
