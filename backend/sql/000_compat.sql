-- Lets the database run on PostgreSQL 13 to 17 too (Supabase, Neon, ...):
-- PostgreSQL 18 has uuidv7() built in; older versions get this one.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'uuidv7') THEN
    CREATE FUNCTION public.uuidv7() RETURNS uuid
    LANGUAGE plpgsql VOLATILE AS $f$
    DECLARE
      b bytea := uuid_send(gen_random_uuid());
      ms bigint := floor(extract(epoch FROM clock_timestamp()) * 1000);
    BEGIN
      -- 48-bit Unix time in milliseconds first, so new ids sort by time.
      b := overlay(b PLACING substring(int8send(ms) FROM 3) FROM 1 FOR 6);
      b := set_byte(b, 6, (get_byte(b, 6) & 15) | 112); -- version 7
      RETURN encode(b, 'hex')::uuid;
    END $f$;
  END IF;
END $$;
