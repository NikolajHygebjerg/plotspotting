-- Udvid søgning til søgeord i metadata
CREATE OR REPLACE FUNCTION search_published_pois(p_slug text, p_query text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(json_agg(json_build_object(
    'id', p.id,
    'name', p.name,
    'category', p.category,
    'description', p.description,
    'access_vertex_id', p.access_vertex_id,
    'lat', ST_Y(p.location::geometry),
    'lng', ST_X(p.location::geometry),
    'metadata', p.metadata
  ) ORDER BY
    nullif(regexp_replace(coalesce(p.metadata->>'house_number', ''), '[^0-9]', '', 'g'), '')::int NULLS LAST,
    p.name
  ), '[]'::json)
  FROM pois p
  JOIN events e ON e.id = p.event_id
  WHERE e.public_slug = p_slug
    AND e.status = 'published'
    AND (
      p_query IS NULL OR btrim(p_query) = '' OR
      p.name ILIKE '%' || p_query || '%' OR
      coalesce(p.metadata->>'house_number', '') ILIKE '%' || p_query || '%' OR
      coalesce(p.metadata->>'resident_name', '') ILIKE '%' || p_query || '%' OR
      coalesce(p.metadata->>'search_keywords', '') ILIKE '%' || p_query || '%' OR
      coalesce(p.description, '') ILIKE '%' || p_query || '%'
    );
$$;
