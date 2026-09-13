-- Run each statement individually in DBeaver (on the actual Postgres
-- connection, port 5432 — not MariaDB, port 3306, same mixup as before)
-- — not as one batch. CREATE DATABASE can't run in the same
-- transaction as other statements.
--
-- A "tandoor_db" database already exists on this instance from a
-- previous attempt. Check what's in it first before deciding which
-- path below to take:
--
--   \c tandoor_db
--   \dt
--
-- If it's empty (no tables, or just Django's default migration
-- tracking), Path A is fine — just take ownership of it fresh.
-- If it has real recipe data you want to keep, use Path A but skip
-- DROP DATABASE, or restore from a backup instead.

-- Replace CHANGE_ME with a real generated password, e.g.:
--   openssl rand -hex 24

-- ── Path A: start fresh (drops any existing tandoor_db) ──
-- Run first, alone:
-- SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'tandoor_db';
-- Run second, alone:
-- DROP DATABASE IF EXISTS tandoor_db;

-- ── Both paths continue from here ──
CREATE USER tandoor WITH PASSWORD 'CHANGE_ME';

-- Only needed if you dropped it above (Path A) or it never existed:
CREATE DATABASE tandoor_db OWNER tandoor TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C';

GRANT ALL PRIVILEGES ON DATABASE tandoor_db TO tandoor;

-- If tandoor_db already existed and you're just taking ownership of it
-- without recreating (Path B — keeping existing data), run this
-- instead of the CREATE DATABASE line above:
-- ALTER DATABASE tandoor_db OWNER TO tandoor;
