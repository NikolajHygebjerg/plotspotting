-- Legacy events oprettet uden konto har created_by = NULL.
-- Giv indloggede brugere adgang til at overtage og flytte dem til workspace.

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
      OR EXISTS (
        SELECT 1
        FROM events e
        WHERE e.id = p_event_id
          AND e.organization_id IS NULL
          AND e.created_by IS NULL
      )
    );
$$;

CREATE OR REPLACE FUNCTION assign_event_to_organization(
  p_event_id uuid,
  p_organization_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_event events%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT is_org_member(
    p_organization_id,
    ARRAY['owner', 'admin', 'editor']::org_member_role[]
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  IF v_event.organization_id IS NOT NULL THEN
    IF v_event.organization_id = p_organization_id THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'event_in_other_workspace';
  END IF;

  IF NOT can_edit_event(p_event_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE events
  SET
    organization_id = p_organization_id,
    created_by = coalesce(created_by, auth.uid()),
    updated_at = now()
  WHERE id = p_event_id;
END;
$$;
