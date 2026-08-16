-- POI metadata (husnummer, beboernavn) i save/load

CREATE OR REPLACE FUNCTION get_event_for_edit(p_event_id uuid, p_edit_code text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
BEGIN
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
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
      'center_lat', ST_Y(v_event.center::geometry),
      'center_lng', ST_X(v_event.center::geometry)
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

CREATE OR REPLACE FUNCTION save_event_graph(
  p_event_id uuid,
  p_edit_code text,
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
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
    RAISE EXCEPTION 'invalid_edit_code';
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

-- Søg publicerede POI'er på navn, husnummer eller beboer
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
      coalesce(p.description, '') ILIKE '%' || p_query || '%'
    );
$$;

GRANT EXECUTE ON FUNCTION search_published_pois(text, text) TO anon, authenticated;
