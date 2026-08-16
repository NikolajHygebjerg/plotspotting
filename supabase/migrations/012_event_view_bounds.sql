-- Større pan/zoom-område for gæster end selve tegningens georef (events.bounds)
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS view_bounds GEOGRAPHY(POLYGON, 4326);

CREATE OR REPLACE FUNCTION save_event_area(
  p_event_id uuid,
  p_edit_code text,
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
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
    RAISE EXCEPTION 'invalid_edit_code';
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

CREATE OR REPLACE FUNCTION get_event_for_edit(p_event_id uuid, p_edit_code text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
  v_bounds geometry;
  v_view_bounds geometry;
BEGIN
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
    RAISE EXCEPTION 'invalid_edit_code';
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  v_bounds := v_event.bounds::geometry;
  v_view_bounds := coalesce(v_event.view_bounds, v_event.bounds)::geometry;

  RETURN json_build_object(
    'event', json_build_object(
      'id', v_event.id,
      'name', v_event.name,
      'description', v_event.description,
      'status', v_event.status,
      'public_slug', v_event.public_slug,
      'center_lat', ST_Y(v_event.center::geometry),
      'center_lng', ST_X(v_event.center::geometry),
      'basemap_url', v_event.basemap_url,
      'basemap_status', v_event.basemap_status,
      'bounds_south', CASE WHEN v_bounds IS NOT NULL THEN ST_YMin(v_bounds) END,
      'bounds_west', CASE WHEN v_bounds IS NOT NULL THEN ST_XMin(v_bounds) END,
      'bounds_north', CASE WHEN v_bounds IS NOT NULL THEN ST_YMax(v_bounds) END,
      'bounds_east', CASE WHEN v_bounds IS NOT NULL THEN ST_XMax(v_bounds) END,
      'view_bounds_south', CASE WHEN v_view_bounds IS NOT NULL THEN ST_YMin(v_view_bounds) END,
      'view_bounds_west', CASE WHEN v_view_bounds IS NOT NULL THEN ST_XMin(v_view_bounds) END,
      'view_bounds_north', CASE WHEN v_view_bounds IS NOT NULL THEN ST_YMax(v_view_bounds) END,
      'view_bounds_east', CASE WHEN v_view_bounds IS NOT NULL THEN ST_XMax(v_view_bounds) END
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
    'public_slug', e.public_slug,
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
