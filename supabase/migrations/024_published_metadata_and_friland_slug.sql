-- Ensure published meta RPC returns metadata (lydvandring, skattejagt, m.m.)
-- and fix Friland slug collision (old empty "friland" vs current "friland-2").

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

-- Retire older published Friland duplicate without lydvandring metadata.
UPDATE events
SET
  status = 'archived',
  public_slug = 'friland-legacy-' || left(id::text, 8)
WHERE status = 'published'
  AND public_slug = 'friland'
  AND coalesce(metadata, '{}'::jsonb) = '{}'::jsonb;

-- Promote the current Friland event to the canonical slug.
UPDATE events
SET public_slug = 'friland'
WHERE status = 'published'
  AND public_slug = 'friland-2'
  AND metadata ? 'audio_tours';
