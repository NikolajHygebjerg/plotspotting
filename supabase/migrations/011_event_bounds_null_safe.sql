-- Undgå fejl når events.bounds er NULL (ældre events uden område)
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
    'bounds_east', CASE WHEN e.bounds IS NOT NULL THEN ST_XMax(e.bounds::geometry) END
  )
  FROM events e
  WHERE e.public_slug = p_slug AND e.status = 'published';
$$;
