-- Enforce even team sizes for finger_soccer in nx_room_set_capacity and nx_start_match too
-- (matching nx_start_room_match and client RoomCapacity).

create or replace function public.nx_room_set_capacity(p_room uuid, p_capacity integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms; b record; sel int; g text; cap int := p_capacity;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if r.status = 'playing' then raise exception 'room already started'; end if;
  g := coalesce(r.selected_game, r.game);
  select * into b from public.nx_game_bounds(g);
  if cap is null then raise exception 'capacity required'; end if;
  if cap < b.min_seats then raise exception 'this game needs at least % players', b.min_seats; end if;
  if cap > b.max_seats then raise exception 'this game takes at most % players', b.max_seats; end if;
  -- Team category: only finger_soccer is two-equal-sides today, but the guard is written by
  -- category so a future team game inherits it instead of needing a new migration.
  if g = 'finger_soccer' and cap % 2 <> 0 then raise exception 'team games need two equal sides'; end if;
  sel := public._nx_room_selected(p_room);
  if cap < sel then raise exception '% players are already picked (remove players first)', sel; end if;
  update public.nx_rooms set seats = cap, updated_at = now() where id = p_room;
  return public.nx_room_capacity(p_room);
end $$;

create or replace function public.nx_start_match(p_room uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); r public.nx_rooms; b record; ids uuid[]; nm text[]; mid uuid; sd bigint; n int; cap int;
begin
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.host <> me and not r.quick then raise exception 'host only'; end if;
  if r.status = 'playing' and r.match_id is not null then
    return jsonb_build_object('match_id', r.match_id, 'already', true);
  end if;
  select * into b from public.nx_game_bounds(r.game);
  cap := greatest(b.min_seats, least(coalesce(r.seats, b.max_seats), b.max_seats));
  select array_agg(rp.user_id order by rp.seat), array_agg(coalesce(p.username, 'Pilot') order by rp.seat), count(*)
    into ids, nm, n
    from public.nx_room_players rp left join public.profiles p on p.id = rp.user_id where rp.room_id = p_room;
  if n < b.min_seats then raise exception 'need % players', b.min_seats; end if;
  if n > cap then raise exception 'this room takes at most % players', cap; end if;
  if r.game = 'finger_soccer' and n % 2 <> 0 then raise exception 'team games need two equal sides'; end if;
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into public.nx_matches(room_id, game, players, names, seed, settings) values (p_room, r.game, ids, nm, sd, r.settings)
  returning id into mid;
  update public.nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', sd);
end $$;
