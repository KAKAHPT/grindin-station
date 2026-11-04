-- Runs once, when the grindin-station-db accessory starts on an empty data directory
-- (docker-entrypoint-initdb.d). Connected as POSTGRES_USER (grindin, superuser) to POSTGRES_DB (postgres).
-- The app connects as grindin_app (no superuser): it owns the four databases, so migrations can create
-- tables; grindin stays for the accessory itself and the backups. Its password comes from the
-- accessory's POSTGRES_APP_PASSWORD (\getenv, psql 15+).
-- Extensions are per database: postgis only where the app tables live; pgcrypto (gen_random_uuid) everywhere.
-- They need a superuser, so they are created here, not by the app.

\getenv app_password POSTGRES_APP_PASSWORD
CREATE ROLE grindin_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_password';

CREATE DATABASE grindin_station_production OWNER grindin_app;
CREATE DATABASE grindin_station_production_cache OWNER grindin_app;
CREATE DATABASE grindin_station_production_queue OWNER grindin_app;
CREATE DATABASE grindin_station_production_cable OWNER grindin_app;

\connect grindin_station_production
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

\connect grindin_station_production_cache
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\connect grindin_station_production_queue
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\connect grindin_station_production_cable
CREATE EXTENSION IF NOT EXISTS pgcrypto;
