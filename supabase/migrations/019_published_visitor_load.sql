-- Robust published graph load + status in meta + publish auth aligned with can_edit_event

CREATE OR REPLACE FUNCTION get_event_graph_by_slug(p_slug text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event_id uuid;
BEGIN
  SELECT id INTO v_event_id
  FROM events
  WHERE public_slug = p_slug AND status = 'published';

  IF v_event_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN json_build_object(
    'vertices', (
      SELECT coalesce(json_agg(json_build_object(
        'id', v.id,
        'lat', ST_Y(v.location::geometry),
        'lng', ST_X(v.location::geometry),
        'label', v.label,
        'is_entrance', v.is_entrance
      ) ORDER BY v.created_at), '[]'::json)
      FROM path_vertices v WHERE v.event_id = v_event_id
    ),
    'edges', (
      SELECT coalesce(json_agg(json_build_object(
        'id', ed.id,
        'from_id', ed.from_vertex_id,
        'to_id', ed.to_vertex_id,
        'length_meters', ed.length_meters,
        'bidirectional', ed.bidirectional,
        'coordinates', ST_AsGeoJSON(ed.geometry::geometry)::json -> 'coordinates'
      ) ORDER BY ed.created_at), '[]'::json)
      FROM path_edges ed WHERE ed.event_id = v_event_id
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
      FROM pois p WHERE p.event_id = v_event_id
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_event_graph_by_slug(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION get_event_meta_by_slug(p_slug text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT json_build_object(
    'id', e.id,
    'name', e.name,
    'description', e.description,
    'status', e.status::text,
    'public_slug', e.public_slug,
    'metadata', e.metadata,
    'center_lat', ST_Y(e.center::geometry),
    'center_lng', ST_X(e.center::geometry),
    'basemap_url', e.basemap_url,
    'basemap_status', e.basemap_status,
    'bounds_south', CASE WHEN e.bounds IS NOT NULL THEN ST_YMin(e.bounds::geometry) END,
    'bounds_west', CASE WHEN e.bounds IS NOT NULL THEN ST_XMin(e.bounds::geometry) END,
    'bounds_north', CASE WHEN e.bounds IS NOT NULL THEN ST_YMax(e.bounds::geometry) END,
    'bounds_east', CASE WHEN e.bounds IS NOT NULL THEN ST_XMax(e.bounds::geometry) END,
    'view_bounds_south', CASE
      WHEN coalesce(e.view_bounds, e.bounds) IS NOT NULL THEN ST_YMin(coalesce(e.view_bounds, e.bounds)::geometry)
    END,
    'view_bounds_west', CASE
      WHEN coalesce(e.view_bounds, e.bounds) IS NOT NULL THEN ST_XMin(coalesce(e.view_bounds, e.bounds)::geometry)
    END,
    'view_bounds_north', CASE
      WHEN coalesce(e.view_bounds, e.bounds) IS NOT NULL THEN ST_YMax(coalesce(e.view_bounds, e.bounds)::geometry)
    END,
    'view_bounds_east', CASE
      WHEN coalesce(e.view_bounds, e.bounds) IS NOT NULL THEN ST_XMax(coalesce(e.view_bounds, e.bounds)::geometry)
    END
  )
  FROM events e
  WHERE e.public_slug = p_slug AND e.status = 'published';
$$;

GRANT EXECUTE ON FUNCTION get_event_meta_by_slug(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION publish_event(p_event_id uuid, p_edit_code text DEFAULT '')
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
  IF NOT can_edit_event(p_event_id, nullif(p_edit_code, '')) THEN
    RAISE EXCEPTION 'invalid_edit_code';
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

GRANT EXECUTE ON FUNCTION publish_event(uuid, text) TO anon, authenticated;
