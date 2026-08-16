-- Platform: brugere, organisationer og hybrid adgang (login + edit-kode)

CREATE TYPE org_member_role AS ENUM ('owner', 'admin', 'editor', 'viewer');
CREATE TYPE org_kind AS ENUM ('personal', 'customer', 'agency');

CREATE TABLE profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_self_read ON profiles
  FOR SELECT USING (id = auth.uid());

CREATE POLICY profiles_self_update ON profiles
  FOR UPDATE USING (id = auth.uid());

CREATE TABLE organizations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  slug            TEXT NOT NULL UNIQUE,
  kind            org_kind NOT NULL DEFAULT 'personal',
  plan            TEXT NOT NULL DEFAULT 'free',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX organizations_slug_idx ON organizations (slug);

CREATE TRIGGER organizations_updated_at
  BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

CREATE TABLE organization_members (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role              org_member_role NOT NULL DEFAULT 'editor',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id)
);

CREATE INDEX organization_members_user_idx ON organization_members (user_id);
CREATE INDEX organization_members_org_idx ON organization_members (organization_id);

ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY org_members_self_read ON organization_members
  FOR SELECT USING (user_id = auth.uid());

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users (id) ON DELETE SET NULL;

CREATE INDEX events_organization_idx ON events (organization_id) WHERE organization_id IS NOT NULL;

CREATE OR REPLACE FUNCTION can_edit_event(p_event_id uuid, p_edit_code text DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    (
      p_edit_code IS NOT NULL
      AND p_edit_code <> ''
      AND EXISTS (
        SELECT 1 FROM events
        WHERE id = p_event_id AND edit_code = p_edit_code
      )
    )
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM events e
        JOIN organization_members om ON om.organization_id = e.organization_id
        WHERE e.id = p_event_id
          AND om.user_id = auth.uid()
          AND om.role IN ('owner', 'admin', 'editor')
      )
    );
$$;

CREATE OR REPLACE FUNCTION verify_edit_code(p_event_id uuid, p_edit_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT can_edit_event(p_event_id, p_edit_code);
$$;

CREATE OR REPLACE FUNCTION is_org_member(
  p_organization_id uuid,
  p_roles org_member_role[] DEFAULT ARRAY['owner', 'admin', 'editor', 'viewer']::org_member_role[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = p_organization_id
      AND user_id = auth.uid()
      AND role = ANY (p_roles)
  );
$$;

CREATE OR REPLACE FUNCTION bootstrap_user_account(p_display_name text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_name text;
  v_org_id uuid;
  v_org_slug text;
  v_suffix int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  INSERT INTO profiles (id, display_name)
  VALUES (v_user_id, nullif(trim(p_display_name), ''))
  ON CONFLICT (id) DO UPDATE
    SET display_name = coalesce(excluded.display_name, profiles.display_name),
        updated_at = now();

  IF EXISTS (SELECT 1 FROM organization_members WHERE user_id = v_user_id) THEN
    RETURN json_build_object('bootstrapped', false);
  END IF;

  v_name := coalesce(nullif(trim(p_display_name), ''), 'Mit workspace');
  v_org_slug := slugify(v_name);

  WHILE EXISTS (SELECT 1 FROM organizations WHERE slug = v_org_slug) LOOP
    v_suffix := v_suffix + 1;
    v_org_slug := slugify(v_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO organizations (name, slug, kind, plan)
  VALUES (v_name, v_org_slug, 'personal', 'free')
  RETURNING id INTO v_org_id;

  INSERT INTO organization_members (organization_id, user_id, role)
  VALUES (v_org_id, v_user_id, 'owner');

  RETURN json_build_object(
    'bootstrapped', true,
    'organization_id', v_org_id,
    'organization_slug', v_org_slug
  );
END;
$$;

GRANT EXECUTE ON FUNCTION bootstrap_user_account(text) TO authenticated;

CREATE OR REPLACE FUNCTION list_my_organizations()
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.name), '[]'::json)
  FROM (
    SELECT
      o.id,
      o.name,
      o.slug,
      o.kind::text AS kind,
      o.plan,
      om.role::text AS role
    FROM organizations o
    JOIN organization_members om ON om.organization_id = o.id
    WHERE om.user_id = auth.uid()
  ) t;
$$;

GRANT EXECUTE ON FUNCTION list_my_organizations() TO authenticated;

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
      e.edit_code,
      e.updated_at
    FROM events e
    WHERE e.organization_id = p_organization_id
      AND is_org_member(p_organization_id, ARRAY['owner', 'admin', 'editor', 'viewer']::org_member_role[])
  ) t;
$$;

GRANT EXECUTE ON FUNCTION list_organization_events(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION create_organization(
  p_name text,
  p_kind org_kind DEFAULT 'customer'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_slug text;
  v_suffix int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  v_slug := slugify(p_name);
  WHILE EXISTS (SELECT 1 FROM organizations WHERE slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(p_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO organizations (name, slug, kind, plan)
  VALUES (p_name, v_slug, p_kind, 'free')
  RETURNING id INTO v_org_id;

  INSERT INTO organization_members (organization_id, user_id, role)
  VALUES (v_org_id, v_user_id, 'owner');

  RETURN json_build_object(
    'id', v_org_id,
    'name', p_name,
    'slug', v_slug,
    'kind', p_kind::text,
    'plan', 'free',
    'role', 'owner'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION create_organization(text, org_kind) TO authenticated;

CREATE OR REPLACE FUNCTION create_outdoor_event(
  p_name text,
  p_description text DEFAULT NULL,
  p_center_lat double precision DEFAULT NULL,
  p_center_lng double precision DEFAULT NULL,
  p_organization_id uuid DEFAULT NULL
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
  IF p_organization_id IS NOT NULL THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'not_authenticated';
    END IF;
    IF NOT is_org_member(
      p_organization_id,
      ARRAY['owner', 'admin', 'editor']::org_member_role[]
    ) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
  END IF;

  v_code := encode(gen_random_bytes(16), 'hex');
  v_slug := slugify(p_name);

  WHILE EXISTS (SELECT 1 FROM events WHERE public_slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(p_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO events (name, description, mode, status, edit_code, center, organization_id, created_by)
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
    END,
    p_organization_id,
    auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_code;
END;
$$;

GRANT EXECUTE ON FUNCTION create_outdoor_event(text, text, double precision, double precision, uuid) TO anon, authenticated;

DROP FUNCTION IF EXISTS create_outdoor_event(text, text, double precision, double precision);

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

CREATE POLICY organizations_member_read ON organizations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_members om
      WHERE om.organization_id = id AND om.user_id = auth.uid()
    )
  );
