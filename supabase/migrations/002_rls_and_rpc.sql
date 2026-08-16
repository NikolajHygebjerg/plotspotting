-- RLS: public read for published events + organizer RPCs (edit_code)

-- ---------------------------------------------------------------------------
-- Read policies — child tables follow parent event status
-- ---------------------------------------------------------------------------

CREATE POLICY path_vertices_public_read ON path_vertices
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND e.status = 'published'
    )
  );

CREATE POLICY path_edges_public_read ON path_edges
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND e.status = 'published'
    )
  );

CREATE POLICY pois_public_read ON pois
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND e.status = 'published'
    )
  );

CREATE POLICY floor_plans_public_read ON floor_plans
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM events e
      WHERE e.id = event_id AND e.status = 'published'
    )
  );

-- Routing graph view inherits from underlying tables; grant select to anon/authenticated
GRANT SELECT ON event_routing_graph TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helper: slugify event name
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION slugify(input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT trim(both '-' from regexp_replace(lower(coalesce(input, '')), '[^a-z0-9]+', '-', 'g'));
$$;

-- ---------------------------------------------------------------------------
-- RPC: create outdoor event (returns id + edit_code once)
-- ---------------------------------------------------------------------------

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

GRANT EXECUTE ON FUNCTION create_outdoor_event(text, text, double precision, double precision) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: verify edit_code for an event
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION verify_edit_code(p_event_id uuid, p_edit_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM events
    WHERE id = p_event_id AND edit_code = p_edit_code
  );
$$;

-- ---------------------------------------------------------------------------
-- RPC: publish event (organizer)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION publish_event(p_event_id uuid, p_edit_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_slug text;
BEGIN
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
    RAISE EXCEPTION 'invalid_edit_code';
  END IF;

  SELECT coalesce(public_slug, slugify(name)) INTO v_slug FROM events WHERE id = p_event_id;

  UPDATE events
  SET
    status = 'published',
    public_slug = v_slug,
    published_at = now()
  WHERE id = p_event_id;

  RETURN v_slug;
END;
$$;

GRANT EXECUTE ON FUNCTION publish_event(uuid, text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC: fetch routing graph by public slug
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_event_graph_by_slug(p_slug text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT graph
  FROM event_routing_graph g
  JOIN events e ON e.id = g.event_id
  WHERE e.public_slug = p_slug AND e.status = 'published';
$$;

GRANT EXECUTE ON FUNCTION get_event_graph_by_slug(text) TO anon, authenticated;
