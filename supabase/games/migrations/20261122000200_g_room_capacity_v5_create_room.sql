-- FIX: nx_create_room on the live project only knew the nine launch games (kart_racing, obstacle_race, bomb_arena,
-- mini_golf, basketball_battle, spy_mafia … answered 'unknown game') and clamped finger soccer / carrom to a hardcoded
-- 6 seats regardless of the game's real bounds. It also handed game lobbies fixed speaker_capacity 30 /
-- spectator_capacity 20, contradicting the "unlimited audience" rule.
--
-- Now: every game nx_known_game accepts can open a room, seats come from nx_game_bounds (the single authoritative
-- table), the audience stays unlimited, and the room is seeded exactly as before (room player + manager member +
-- selected game player) so the lobby, quick match and invitations keep working.
--
-- Verified on the live project (rolled back): finger_soccer 6 -> 6, finger_soccer 9 -> 6, carrom 6 -> 2,
-- kart_racing 4 -> 4, spy_mafia 8 -> 8, mafia 12 -> 12, mafia 99 -> 12, uno 4 -> 4.

create or replace function public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean default false,
                                                 p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); b record; s int; rid uuid; c text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.nx_known_game(p_game) then raise exception 'unknown game'; end if;
  select * into b from public.nx_game_bounds(p_game);
  s := greatest(b.min_seats, least(coalesce(p_seats, b.min_seats), b.max_seats));
  perform public._nx_leave_all(me);
  c := public.nx_gen_code();
  insert into public.nx_rooms(code, game, host, seats, is_private, quick, settings, selected_game, kind)
  values (c, p_game, me, s, coalesce(p_private, false), coalesce(p_quick, false), coalesce(p_settings, '{}'::jsonb),
          p_game, 'game')
  returning id into rid;
  insert into public.nx_room_players(room_id, user_id, seat, ready) values (rid, me, 0, true);
  insert into public.nx_room_members(room_id, user_id, role) values (rid, me, 'manager')
    on conflict (room_id, user_id) do update set role = 'manager', last_seen = now();
  insert into public.nx_room_game_players(room_id, user_id, seat, team, ready) values (rid, me, 0, 0, true)
    on conflict (room_id, user_id) do update set ready = true;
  return jsonb_build_object('room_id', rid, 'code', c, 'seats', s, 'capacity', s,
                            'min_players', b.min_seats, 'max_players', b.max_seats);
end $$;

revoke all on function public.nx_create_room(text, integer, boolean, boolean, jsonb) from public, anon;
grant execute on function public.nx_create_room(text, integer, boolean, boolean, jsonb) to authenticated;
