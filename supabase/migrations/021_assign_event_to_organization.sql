-- Flyt et kort uden workspace til en organisation brugeren kan redigere i.

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

GRANT EXECUTE ON FUNCTION assign_event_to_organization(uuid, uuid) TO authenticated;
