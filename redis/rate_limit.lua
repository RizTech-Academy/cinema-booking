-- Atomic per-customer booking rate limiter. INCR then EXPIRE as two separate
-- commands has a crash-in-between bug (a key left with no expiry); a Lua script
-- makes them one atomic operation.
--   KEYS[1] = the counter key (e.g. rl:book:customer:2)
--   ARGV[1] = the window in seconds (e.g. 60)
-- Returns the current count; the caller rejects when it exceeds the limit.
local c = redis.call('INCR', KEYS[1])
if c == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return c
