-- Return edit_code in get_event_for_edit so authorized editors can persist it locally
-- (org membership or valid edit code).

CREATE OR REPLACE FUNCTION get_event_for_edit(p_event_id uuid, p_edit_code text DEFAULT '')
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
BEGIN
  IF NOT can_edit_event(p_event_id, nullif(p_edit_code, '')) THEN
    RAISE EXCEPTION 'invalid_edit_code';
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
      'edit_code', v_event.edit_code,
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

GRANT EXECUTE ON FUNCTION get_event_for_edit(uuid, text) TO anon, authenticated;
