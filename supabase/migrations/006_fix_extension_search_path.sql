-- Supabase installerer pgcrypto/postgis i schema "extensions".
-- SECURITY DEFINER-funktioner med search_path = public kan ikke finde gen_random_bytes m.m.

CREATE OR REPLACE FUNCTION create_outdoor_event(
  p_name text,
  p_description text DEFAULT NULL,
  p_center_lat double precision DEFAULT NULL,
  p_center_lng double precision DEFAULT NULL
)
RETURNS TABLE (event_id uuid, edit_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
  v_code text;
  v_slug text;
  v_suffix int := 0;
BEGIN
  v_code := encode(gen_random_bytes(16), 'hex');
  v_slug := slugify(p_name);

  WHILE EXISTS (SELECT 1 FROM events WHERE public_slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(p_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO events (name, description, mode, status, edit_code, center)
  VALUES (
    p_name,
    p_description,
    'outdoor',
    'draft',
    v_code,
    CASE
      WHEN p_center_lat IS NOT NULL AND p_center_lng IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
      ELSE NULL
    END
  )
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_code;
END;
$$;
