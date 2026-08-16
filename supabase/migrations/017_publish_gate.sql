-- Publish gate: kræver workspace-plan med udgivelsesadgang (betaling kommer senere)

CREATE OR REPLACE FUNCTION organization_can_publish(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_organization_id
      AND plan IN ('publish', 'pro', 'agency')
  );
$$;

CREATE OR REPLACE FUNCTION can_publish_event(p_event_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM events WHERE id = p_event_id) THEN false
    WHEN (SELECT status FROM events WHERE id = p_event_id) = 'published' THEN true
    WHEN (SELECT organization_id FROM events WHERE id = p_event_id) IS NULL THEN true
    ELSE organization_can_publish(
      (SELECT organization_id FROM events WHERE id = p_event_id)
    )
  END;
$$;

CREATE OR REPLACE FUNCTION get_publish_status(p_event_id uuid, p_edit_code text DEFAULT '')
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
  IF NOT can_edit_event(p_event_id, nullif(p_edit_code, '')) THEN
    RAISE EXCEPTION 'invalid_edit_code';
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

GRANT EXECUTE ON FUNCTION get_publish_status(uuid, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION publish_event(p_event_id uuid, p_edit_code text)
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
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
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

-- Bureau-workspaces får udgivelsesadgang; eksisterende bureau opdateres
UPDATE organizations SET plan = 'publish' WHERE kind = 'agency';

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
  v_plan text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  v_plan := CASE WHEN p_kind = 'agency' THEN 'publish' ELSE 'free' END;

  v_slug := slugify(p_name);
  WHILE EXISTS (SELECT 1 FROM organizations WHERE slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := slugify(p_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO organizations (name, slug, kind, plan)
  VALUES (p_name, v_slug, p_kind, v_plan)
  RETURNING id INTO v_org_id;

  INSERT INTO organization_members (organization_id, user_id, role)
  VALUES (v_org_id, v_user_id, 'owner');

  RETURN json_build_object(
    'id', v_org_id,
    'name', p_name,
    'slug', v_slug,
    'kind', p_kind::text,
    'plan', v_plan,
    'role', 'owner'
  );
END;
$$;

-- Manuel aktivering (indtil Stripe): workspace-ejer kan anmode — her direkte RPC til test/support
CREATE OR REPLACE FUNCTION grant_organization_publish(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT is_org_member(
    p_organization_id,
    ARRAY['owner', 'admin']::org_member_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE organizations
  SET plan = 'publish', updated_at = now()
  WHERE id = p_organization_id
    AND plan = 'free';
END;
$$;

GRANT EXECUTE ON FUNCTION grant_organization_publish(uuid) TO authenticated;
