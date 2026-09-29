-- Realistic seed data, in dependency order (screens & movies before shows,
-- before bookings). Seats are generated with generate_series, not typed by hand.

INSERT INTO screens (name, total_seats) VALUES
  ('Screen 1', 100),
  ('Screen 2', 80),
  ('Screen 3 (IMAX)', 150);

-- 100 seats for screen 1 (rows A-J, ten each), 80 for screen 2 (A-H), 150 for
-- screen 3 (A-O). chr(64 + r) turns 1 -> 'A', 2 -> 'B', ...
INSERT INTO seats (screen_id, row_label, seat_num)
SELECT 1, chr(64 + r), n FROM generate_series(1,10) AS r, generate_series(1,10) AS n;
INSERT INTO seats (screen_id, row_label, seat_num)
SELECT 2, chr(64 + r), n FROM generate_series(1,8)  AS r, generate_series(1,10) AS n;
INSERT INTO seats (screen_id, row_label, seat_num)
SELECT 3, chr(64 + r), n FROM generate_series(1,15) AS r, generate_series(1,10) AS n;

INSERT INTO movies (title, language, duration_min, released_on) VALUES
  ('Laapataa Ladies',   'Hindi',   122, '2024-03-01'),
  ('Kantara',           'Kannada', 148, '2022-09-30'),
  ('The Kashmir Files', 'Hindi',   170, '2022-03-11'),
  ('Ponniyin Selvan',   'Tamil',   167, '2022-09-30'),
  ('3 Idiots',          'Hindi',   170, '2009-12-25');

INSERT INTO shows (movie_id, screen_id, starts_at, price_paise) VALUES
  (1, 1, '2026-09-28 12:30:00+00', 25000),  -- Laapataa Ladies, Screen 1, matinee ₹250
  (2, 3, '2026-09-28 15:30:00+00', 40000),  -- Kantara, IMAX ₹400
  (3, 2, '2026-09-29 09:30:00+00', 20000),  -- The Kashmir Files, Screen 2 ₹200
  (4, 3, '2026-09-29 13:00:00+00', 40000),  -- Ponniyin Selvan, IMAX ₹400
  (1, 1, '2026-09-29 15:30:00+00', 30000);  -- Laapataa Ladies, Screen 1, evening ₹300

INSERT INTO customers (name, email, phone) VALUES
  ('Asha Kulkarni',  'asha@example.in',  '9876500001'),
  ('Ravi Deshmukh',  'ravi@example.in',  '9876500002'),
  ('Priya Nair',     'priya@example.in', '9876500003'),
  ('Sunil Joshi',    NULL,               '9876500004');  -- a walk-up, no email
