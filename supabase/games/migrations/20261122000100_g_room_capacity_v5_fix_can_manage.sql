-- FIX: `_nx_room_can_manage` returned NULL for non-members (false OR NULL = NULL), so `if not can_manage then raise`
-- never fired for a stranger. Every manager-only guard (capacity, lock, kick, pick, start, change game) must see a
-- real boolean; this makes the helper total (false instead of NULL).
--
-- Verified against the live games project with a two-user dry run (claims switched inside a transaction, rolled back):
--   guest -> set_capacity / set_locked / kick / select_players / start_room_match / change_game = "manager only"
--   member -> nx_room_capacity still readable (needed by the room header)

create or replace function public._nx_room_can_manage(p_room uuid) returns boolean
 language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    exists (select 1 from public.nx_rooms r where r.id = p_room and r.host = auth.uid())
    or public.nx_room_member_role(p_room) = 'manager', false)
$$;
