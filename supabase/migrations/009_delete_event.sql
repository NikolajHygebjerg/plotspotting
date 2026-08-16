-- Slet event (kræver edit-kode). Underliggende data slettes via CASCADE.

CREATE OR REPLACE FUNCTION delete_event(
  p_event_id uuid,
  p_edit_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT verify_edit_code(p_event_id, p_edit_code) THEN
    RAISE EXCEPTION 'invalid_edit_code';
  END IF;

  DELETE FROM events WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_event(uuid, text) TO anon, authenticated;
