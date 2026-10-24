-- Friendship membership is private to the two people in that relationship.
CREATE OR REPLACE FUNCTION public.are_friends(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL OR (v_uid IS DISTINCT FROM p_a AND v_uid IS DISTINCT FROM p_b) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.friendships
    WHERE user_a = least(p_a, p_b) AND user_b = greatest(p_a, p_b)
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.are_friends(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.are_friends(uuid, uuid) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
