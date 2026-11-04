-- Runs once, when the grindin-station-db accessory starts on an empty data directory
-- (docker-entrypoint-initdb.d). Connected as POSTGRES_USER (grindin, superuser) to POSTGRES_DB (postgres).
-- Extensions are per database: postgis only where the app tables live; pgcrypto (gen_random_uuid) everywhere.

CREATE DATABASE grindin_station_production;
CREATE DATABASE grindin_station_production_cache;
CREATE DATABASE grindin_station_production_queue;
CREATE DATABASE grindin_station_production_cable;

\connect grindin_station_production
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

\connect grindin_station_production_cache
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\connect grindin_station_production_queue
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\connect grindin_station_production_cable
CREATE EXTENSION IF NOT EXISTS pgcrypto;
