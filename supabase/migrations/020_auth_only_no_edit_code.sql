-- Auth-only editing: remove edit-code as access mechanism

DROP FUNCTION IF EXISTS find_event_by_edit_code(text);
DROP FUNCTION IF EXISTS verify_edit_code(uuid, text);
DROP FUNCTION IF EXISTS can_edit_event(uuid, text);

CREATE OR REPLACE FUNCTION can_edit_event(p_event_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT auth.uid() IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM events e
        JOIN organization_members om ON om.organization_id = e.organization_id
        WHERE e.id = p_event_id
          AND om.user_id = auth.uid()
          AND om.role IN ('owner', 'admin', 'editor')
      )
      OR EXISTS (
        SELECT 1
        FROM events e
        WHERE e.id = p_event_id
          AND e.organization_id IS NULL
          AND e.created_by = auth.uid()
      )
    );
$$;

CREATE OR REPLACE FUNCTION list_organization_events(p_organization_id uuid)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.updated_at DESC), '[]'::json)
  FROM (
    SELECT
      e.id,
      e.name,
      e.status::text AS status,
      e.public_slug,
      e.updated_at
    FROM events e
    WHERE e.organization_id = p_organization_id
      AND is_org_member(p_organization_id, ARRAY['owner', 'admin', 'editor', 'viewer']::org_member_role[])
  ) t;
$$;

DROP FUNCTION IF EXISTS create_outdoor_event(text, text, double precision, double precision, uuid);

CREATE OR REPLACE FUNCTION create_outdoor_event(
  p_name text,
  p_organization_id uuid,
  p_description text DEFAULT NULL,
  p_center_lat double precision DEFAULT NULL,
  p_center_lng double precision DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
  v_slug text;
  v_suffix int := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'organization_required';
  END IF;

  IF NOT is_org_member(
    p_organization_id,
    ARRAY['owner', 'admin', 'editor']::org_member_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_slug := slugify(p_name);

  WHILE EXISTS (SELECT 1 FROM events WHERE public_slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(p_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO events (name, description, mode, status, center, organization_id, created_by)
  VALUES (
    p_name,
    p_description,
    'outdoor',
    'draft',
    CASE
      WHEN p_center_lat IS NOT NULL AND p_center_lng IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
      ELSE NULL
    END,
    p_organization_id,
    auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_outdoor_event(text, uuid, text, double precision, double precision) TO authenticated;

DROP FUNCTION IF EXISTS get_event_for_edit(uuid, text);

CREATE OR REPLACE FUNCTION get_event_for_edit(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;

  RETURN json_build_object(
    'event', json_build_object(
      'id', v_event.id,
      'name', v_event.name,
      'description', v_event.description,
      'status', v_event.status,
      'public_slug', v_event.public_slug,
      'organization_id', v_event.organization_id,
      'center_lat', ST_Y(v_event.center::geometry),
      'center_lng', ST_X(v_event.center::geometry),
      'basemap_url', v_event.basemap_url,
      'basemap_status', v_event.basemap_status,
      'metadata', v_event.metadata,
      'bounds_south', CASE WHEN v_event.bounds IS NOT NULL THEN ST_YMin(v_event.bounds::geometry) END,
      'bounds_west', CASE WHEN v_event.bounds IS NOT NULL THEN ST_XMin(v_event.bounds::geometry) END,
      'bounds_north', CASE WHEN v_event.bounds IS NOT NULL THEN ST_YMax(v_event.bounds::geometry) END,
      'bounds_east', CASE WHEN v_event.bounds IS NOT NULL THEN ST_XMax(v_event.bounds::geometry) END,
      'view_bounds_south', CASE WHEN coalesce(v_event.view_bounds, v_event.bounds) IS NOT NULL THEN ST_YMin(coalesce(v_event.view_bounds, v_event.bounds)::geometry) END,
      'view_bounds_west', CASE WHEN coalesce(v_event.view_bounds, v_event.bounds) IS NOT NULL THEN ST_XMin(coalesce(v_event.view_bounds, v_event.bounds)::geometry) END,
      'view_bounds_north', CASE WHEN coalesce(v_event.view_bounds, v_event.bounds) IS NOT NULL THEN ST_YMax(coalesce(v_event.view_bounds, v_event.bounds)::geometry) END,
      'view_bounds_east', CASE WHEN coalesce(v_event.view_bounds, v_event.bounds) IS NOT NULL THEN ST_XMax(coalesce(v_event.view_bounds, v_event.bounds)::geometry) END
    ),
    'vertices', (
      SELECT coalesce(json_agg(json_build_object(
        'id', v.id,
        'lat', ST_Y(v.location::geometry),
        'lng', ST_X(v.location::geometry),
        'label', v.label,
        'is_entrance', v.is_entrance
      ) ORDER BY v.created_at), '[]'::json)
      FROM path_vertices v WHERE v.event_id = p_event_id
    ),
    'edges', (
      SELECT coalesce(json_agg(json_build_object(
        'id', ed.id,
        'from_id', ed.from_vertex_id,
        'to_id', ed.to_vertex_id,
        'length_meters', ed.length_meters,
        'coordinates', ST_AsGeoJSON(ed.geometry::geometry)::json -> 'coordinates'
      ) ORDER BY ed.created_at), '[]'::json)
      FROM path_edges ed WHERE ed.event_id = p_event_id
    ),
    'pois', (
      SELECT coalesce(json_agg(json_build_object(
        'id', p.id,
        'name', p.name,
        'category', p.category,
        'description', p.description,
        'access_vertex_id', p.access_vertex_id,
        'lat', ST_Y(p.location::geometry),
        'lng', ST_X(p.location::geometry),
        'metadata', p.metadata
      ) ORDER BY p.sort_order, p.created_at), '[]'::json)
      FROM pois p WHERE p.event_id = p_event_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_event_for_edit(uuid) TO authenticated;

DROP FUNCTION IF EXISTS save_event_graph(uuid, text, jsonb, jsonb, jsonb, double precision, double precision);

CREATE OR REPLACE FUNCTION save_event_graph(
  p_event_id uuid,
  p_vertices jsonb,
  p_edges jsonb,
  p_pois jsonb,
  p_center_lat double precision DEFAULT NULL,
  p_center_lng double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v jsonb;
  v_coords jsonb;
  v_line geometry;
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  DELETE FROM path_edges WHERE event_id = p_event_id;
  DELETE FROM pois WHERE event_id = p_event_id;
  DELETE FROM path_vertices WHERE event_id = p_event_id;

  FOR v IN SELECT * FROM jsonb_array_elements(coalesce(p_vertices, '[]'::jsonb))
  LOOP
    INSERT INTO path_vertices (id, event_id, location, label, is_entrance)
    VALUES (
      (v->>'id')::uuid,
      p_event_id,
      ST_SetSRID(
        ST_MakePoint((v->>'lng')::double precision, (v->>'lat')::double precision),
        4326
      )::geography,
      nullif(v->>'label', ''),
      coalesce((v->>'is_entrance')::boolean, false)
    );
  END LOOP;

  FOR v IN SELECT * FROM jsonb_array_elements(coalesce(p_edges, '[]'::jsonb))
  LOOP
    v_coords := v->'coordinates';
    IF jsonb_array_length(v_coords) >= 2 THEN
      SELECT ST_MakeLine(geom ORDER BY ord) INTO v_line
      FROM (
        SELECT
          ordinality AS ord,
          ST_SetSRID(
            ST_MakePoint(
              (elem->>0)::double precision,
              (elem->>1)::double precision
            ),
            4326
          ) AS geom
        FROM jsonb_array_elements(v_coords) WITH ORDINALITY AS t(elem, ordinality)
      ) pts;
    ELSE
      v_line := NULL;
    END IF;

    INSERT INTO path_edges (
      id, event_id, from_vertex_id, to_vertex_id, geometry, length_meters, bidirectional
    )
    VALUES (
      (v->>'id')::uuid,
      p_event_id,
      (v->>'from_id')::uuid,
      (v->>'to_id')::uuid,
      CASE WHEN v_line IS NOT NULL THEN v_line::geography ELSE NULL END,
      coalesce((v->>'length_meters')::double precision, 0),
      coalesce((v->>'bidirectional')::boolean, true)
    );
  END LOOP;

  FOR v IN SELECT * FROM jsonb_array_elements(coalesce(p_pois, '[]'::jsonb))
  LOOP
    INSERT INTO pois (
      id, event_id, name, category, description, location, access_vertex_id, sort_order, metadata
    )
    VALUES (
      (v->>'id')::uuid,
      p_event_id,
      v->>'name',
      coalesce(v->>'category', 'other'),
      nullif(v->>'description', ''),
      ST_SetSRID(
        ST_MakePoint((v->>'lng')::double precision, (v->>'lat')::double precision),
        4326
      )::geography,
      nullif(v->>'access_vertex_id', '')::uuid,
      coalesce((v->>'sort_order')::integer, 0),
      coalesce(v->'metadata', '{}'::jsonb)
    );
  END LOOP;

  IF p_center_lat IS NOT NULL AND p_center_lng IS NOT NULL THEN
    UPDATE events
    SET center = ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    WHERE id = p_event_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION save_event_graph(uuid, jsonb, jsonb, jsonb, double precision, double precision) TO authenticated;

DROP FUNCTION IF EXISTS save_event_area(uuid, text, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS save_event_area(uuid, text, double precision, double precision, double precision, double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION save_event_area(
  p_event_id uuid,
  p_south double precision,
  p_west double precision,
  p_north double precision,
  p_east double precision,
  p_center_lat double precision DEFAULT NULL,
  p_center_lng double precision DEFAULT NULL,
  p_view_south double precision DEFAULT NULL,
  p_view_west double precision DEFAULT NULL,
  p_view_north double precision DEFAULT NULL,
  p_view_east double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_view_south double precision := coalesce(p_view_south, p_south);
  v_view_west double precision := coalesce(p_view_west, p_west);
  v_view_north double precision := coalesce(p_view_north, p_north);
  v_view_east double precision := coalesce(p_view_east, p_east);
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE events
  SET
    bounds = ST_SetSRID(
      ST_MakePolygon(
        ST_MakeLine(ARRAY[
          ST_MakePoint(p_west, p_south),
          ST_MakePoint(p_east, p_south),
          ST_MakePoint(p_east, p_north),
          ST_MakePoint(p_west, p_north),
          ST_MakePoint(p_west, p_south)
        ])
      ),
      4326
    )::geography,
    view_bounds = ST_SetSRID(
      ST_MakePolygon(
        ST_MakeLine(ARRAY[
          ST_MakePoint(v_view_west, v_view_south),
          ST_MakePoint(v_view_east, v_view_south),
          ST_MakePoint(v_view_east, v_view_north),
          ST_MakePoint(v_view_west, v_view_north),
          ST_MakePoint(v_view_west, v_view_south)
        ])
      ),
      4326
    )::geography,
    center = CASE
      WHEN p_center_lat IS NOT NULL AND p_center_lng IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
      ELSE center
    END
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION save_event_area(uuid, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO authenticated;

DROP FUNCTION IF EXISTS save_event_metadata(uuid, text, jsonb);

CREATE OR REPLACE FUNCTION save_event_metadata(
  p_event_id uuid,
  p_metadata jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE events
  SET metadata = coalesce(p_metadata, '{}'::jsonb)
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION save_event_metadata(uuid, jsonb) TO authenticated;

DROP FUNCTION IF EXISTS set_event_basemap(uuid, text, text, text);

CREATE OR REPLACE FUNCTION set_event_basemap(
  p_event_id uuid,
  p_basemap_url text,
  p_status text DEFAULT 'ready'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE events
  SET
    basemap_url = p_basemap_url,
    basemap_status = p_status
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION set_event_basemap(uuid, text, text) TO authenticated;

DROP FUNCTION IF EXISTS delete_event(uuid, text);

CREATE OR REPLACE FUNCTION delete_event(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  DELETE FROM events WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_event(uuid) TO authenticated;

DROP FUNCTION IF EXISTS get_publish_status(uuid, text);

CREATE OR REPLACE FUNCTION get_publish_status(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
  v_org organizations%ROWTYPE;
  v_allowed boolean;
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  v_allowed := can_publish_event(p_event_id);

  IF v_event.organization_id IS NULL THEN
    RETURN json_build_object(
      'allowed', v_allowed,
      'reason', CASE WHEN v_allowed THEN 'legacy' ELSE 'blocked' END,
      'message', CASE
        WHEN v_allowed THEN 'Klar til publicering'
        ELSE 'Publicering er ikke tilladt for dette kort'
      END,
      'organization_id', null,
      'organization_name', null,
      'plan', null,
      'already_published', v_event.status = 'published'
    );
  END IF;

  SELECT * INTO v_org FROM organizations WHERE id = v_event.organization_id;

  RETURN json_build_object(
    'allowed', v_allowed,
    'reason', CASE
      WHEN v_event.status = 'published' THEN 'already_published'
      WHEN v_allowed THEN 'plan_ok'
      ELSE 'plan_free'
    END,
    'message', CASE
      WHEN v_event.status = 'published' THEN 'Kortet er allerede publiceret'
      WHEN v_allowed THEN 'Klar til publicering'
      ELSE 'Publicering kræver udgivelsesadgang på workspace. Kontakt os for at aktivere — betaling kommer senere.'
    END,
    'organization_id', v_org.id,
    'organization_name', v_org.name,
    'plan', v_org.plan,
    'already_published', v_event.status = 'published'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_publish_status(uuid) TO authenticated;

DROP FUNCTION IF EXISTS publish_event(uuid, text);

CREATE OR REPLACE FUNCTION publish_event(p_event_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_slug text;
  v_name text;
  v_suffix int := 0;
  v_status event_status;
BEGIN
  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_status FROM events WHERE id = p_event_id;

  IF v_status <> 'published' AND NOT can_publish_event(p_event_id) THEN
    RAISE EXCEPTION 'publish_not_allowed';
  END IF;

  SELECT name, coalesce(public_slug, slugify(name))
  INTO v_name, v_slug
  FROM events WHERE id = p_event_id;

  WHILE EXISTS (
    SELECT 1 FROM events WHERE public_slug = v_slug AND id <> p_event_id
  ) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(v_name) || '-' || v_suffix::text;
  END LOOP;

  UPDATE events
  SET status = 'published', public_slug = v_slug, published_at = coalesce(published_at, now())
  WHERE id = p_event_id;

  RETURN v_slug;
END;
$$;

GRANT EXECUTE ON FUNCTION publish_event(uuid) TO authenticated;
