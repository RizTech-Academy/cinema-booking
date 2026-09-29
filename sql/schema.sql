-- Pune Cinemas — the PostgreSQL source of truth.
-- Every choice here is defended in the Database Foundation capstone: bigint
-- identity keys, timestamptz, integer money (paise), CHECK constraints,
-- NOT NULL by default, seats as rows, and the one UNIQUE that makes
-- double-booking impossible.

CREATE TABLE movies (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title        text NOT NULL,
  language     text NOT NULL,
  duration_min int  NOT NULL CHECK (duration_min > 0),
  released_on  date,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE screens (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        text NOT NULL,
  total_seats int  NOT NULL CHECK (total_seats > 0)
);

CREATE TABLE customers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       text NOT NULL,
  email      text UNIQUE,               -- nullable: a walk-up customer may have none
  phone      text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Seats are ROWS, not a count: the requirement is per-seat ("book A3"), so the
-- model must be per-seat. A count cannot say "A3 is taken but A4 is free".
CREATE TABLE seats (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  screen_id bigint NOT NULL REFERENCES screens(id),
  row_label text   NOT NULL,
  seat_num  int    NOT NULL,
  UNIQUE (screen_id, row_label, seat_num)   -- no two "A5"s on one screen
);

-- A show is a movie on a screen at a time, with its own price (matinees differ
-- from evenings). Money is integer paise, never float.
CREATE TABLE shows (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  movie_id    bigint NOT NULL REFERENCES movies(id),
  screen_id   bigint NOT NULL REFERENCES screens(id),
  starts_at   timestamptz NOT NULL,
  price_paise int    NOT NULL CHECK (price_paise > 0)
);

CREATE TABLE bookings (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  show_id     bigint NOT NULL REFERENCES shows(id),
  customer_id bigint NOT NULL REFERENCES customers(id),
  status      text   NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','cancelled')),
  amount_paise int   NOT NULL CHECK (amount_paise >= 0),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- The join table carrying the single most important line in the schema.
CREATE TABLE booking_seats (
  booking_id bigint NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  show_id    bigint NOT NULL REFERENCES shows(id),
  seat_id    bigint NOT NULL REFERENCES seats(id),
  PRIMARY KEY (booking_id, seat_id),
  UNIQUE (show_id, seat_id)          -- <- makes double-booking impossible, at the DB level
);

-- Indexes: foreign keys are indexed (unindexed FKs mean slow lookups and
-- parent-deletes that scan the child). The UNIQUE (show_id, seat_id) already
-- indexes (show_id, seat_id), covering the availability query.
CREATE INDEX ON shows (movie_id);
CREATE INDEX ON shows (screen_id);
CREATE INDEX ON shows (starts_at);
CREATE INDEX ON seats (screen_id);
CREATE INDEX ON bookings (show_id);
CREATE INDEX ON bookings (customer_id);
CREATE INDEX ON booking_seats (seat_id);

-- Full-text search on movie titles (a GIN index scales to a large catalogue;
-- at five movies it is illustrative, but it stems and ranks as LIKE cannot).
CREATE INDEX movies_title_fts ON movies USING gin (to_tsvector('english', title));
