DO $$ BEGIN
   CREATE ROLE :DB_USER WITH LOGIN PASSWORD ':DB_PASSWORD';
EXCEPTION WHEN DUPLICATE_OBJECT THEN
   RAISE NOTICE 'Role :DB_USER already exists, skipping creation.';
END $$;

DO $$ BEGIN
   CREATE DATABASE grindin_station_development OWNER :DB_USER;
EXCEPTION WHEN DUPLICATE_DATABASE THEN
   RAISE NOTICE 'Database grindin_station_development already exists, skipping creation.';
END $$;

DO $$ BEGIN
   CREATE DATABASE grindin_station_test OWNER :DB_USER;
EXCEPTION WHEN DUPLICATE_DATABASE THEN
   RAISE NOTICE 'Database grindin_station_test already exists, skipping creation.';
END $$;

DO $$ BEGIN
   CREATE DATABASE grindin_station_production OWNER :DB_USER;
EXCEPTION WHEN DUPLICATE_DATABASE THEN
   RAISE NOTICE 'Database grindin_station_production already exists, skipping creation.';
END $$;

DO $$ BEGIN
   CREATE DATABASE grindin_station_production_queue OWNER :DB_USER;
EXCEPTION WHEN DUPLICATE_DATABASE THEN
   RAISE NOTICE 'Database grindin_station_production_queue already exists, skipping creation.';
END $$;
