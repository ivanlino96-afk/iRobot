CREATE TABLE IF NOT EXISTS users (id text PRIMARY KEY, email text UNIQUE NOT NULL, password text NOT NULL);
CREATE TABLE IF NOT EXISTS robots (id text PRIMARY KEY, owner_id text REFERENCES users(id), pairing_hash text, pairing_expires bigint);
CREATE TABLE IF NOT EXISTS profiles (robot_id text REFERENCES robots(id), version integer, hash text NOT NULL, body text NOT NULL, PRIMARY KEY(robot_id,version));
CREATE TABLE IF NOT EXISTS programs (id text PRIMARY KEY, robot_id text REFERENCES robots(id), name text NOT NULL, revision integer NOT NULL, family_id text, body jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (robot_id text PRIMARY KEY REFERENCES robots(id), id text NOT NULL, user_id text NOT NULL REFERENCES users(id), boot_id text NOT NULL, scope text NOT NULL, expires bigint NOT NULL, broker_user text NOT NULL, broker_password text NOT NULL);

ALTER TABLE programs ADD COLUMN IF NOT EXISTS family_id text;
CREATE UNIQUE INDEX IF NOT EXISTS program_revision_unique ON programs(family_id,revision);
