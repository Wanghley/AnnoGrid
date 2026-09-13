-- Run this against your existing Postgres as a superuser (e.g. wanghley),
-- connected to any database (the CREATE DATABASE statement can't run
-- inside a transaction block alongside other statements, so run this
-- file with a client that executes each statement separately — psql -f
-- does this correctly; a GUI tool that wraps the whole file in one
-- transaction will fail on the CREATE DATABASE line).
--
-- Replace CHANGE_ME below with a real generated password, e.g.:
--   openssl rand -hex 24

CREATE USER spliit WITH PASSWORD 'CHANGE_ME';

CREATE DATABASE spliit OWNER spliit;

-- Belt-and-suspenders: explicitly grant all privileges on the database
-- to its owner (redundant with OWNER above, but makes the intent
-- explicit and survives if ownership is ever changed later).
GRANT ALL PRIVILEGES ON DATABASE spliit TO spliit;

-- Postgres 15+ revokes CREATE on the public schema from non-owners by
-- default; since spliit owns this database that's already fine, but
-- reconnect to the spliit database and run this too if Prisma's
-- migrations ever complain about schema permissions:
--
--   \c spliit
--   GRANT ALL ON SCHEMA public TO spliit;
