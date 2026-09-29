-- The core operation: book specific seats for a show, as ONE atomic
-- transaction — create the booking row AND claim every seat, together, or do
-- nothing. A single CTE does it in one round trip. The amount is computed in
-- the database from seat count x show price, so it cannot disagree with the
-- seats booked.
--
-- Edit the show id, customer id and seat list to book different seats.
BEGIN;
WITH chosen AS (
  SELECT s.id AS seat_id
  FROM seats s
  WHERE s.screen_id = (SELECT screen_id FROM shows WHERE id = 1)
    AND (s.row_label, s.seat_num) IN (('A', 2), ('A', 3))
),
new_booking AS (
  INSERT INTO bookings (show_id, customer_id, amount_paise)
  SELECT 1, 1, (SELECT count(*) FROM chosen) * (SELECT price_paise FROM shows WHERE id = 1)
  RETURNING id
)
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT (SELECT id FROM new_booking), 1, seat_id FROM chosen;
COMMIT;
