-- Backend ↔ app sync (auth/core project eisstodgncimypdawisy). Forward-only, idempotent, drops nothing.
--
-- Security advisor ERROR "security_definer_view": the three legacy lobby/leaderboard views ran with the view owner's
-- rights, so they bypassed RLS on rooms / room_players / game_ratings / profiles (and exposed profile fields to anon).
-- With security_invoker they apply the caller's RLS. Signed-in callers see the same rows as before (the underlying
-- read policies are `true` / "not private"), so the sibling app that reads them keeps working.
alter view if exists public.room_list set (security_invoker = true);
alter view if exists public.game_room_list set (security_invoker = true);
alter view if exists public.game_leaderboard set (security_invoker = true);
