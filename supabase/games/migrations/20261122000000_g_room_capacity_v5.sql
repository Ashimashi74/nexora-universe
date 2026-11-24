-- ROOM CAPACITY v5 — host-controlled capacity, admission lock and removal, per game category.
--
-- One authoritative capacity table (nx_game_bounds) instead of the five partially conflicting copies that had
-- accumulated in earlier migrations (mafia oscillated between 10 and 12, quiz claimed 21 seats while the quiz engine
-- is a 1v1 duel, carrom claimed 6 while the carrom board is a two-seat duel, finger soccer could not be created with
-- 2v2/3v3 seats). Bounds now follow what the gameplay code actually implements:
--
--   duel       carrom 2, billiards 2, backgammon 2, quiz 2, pool8 2
--   group      ludo 2-4, snakes_ladders 2-4, uno 2-4, kart_racing 2-4, obstacle_race 2-4, bomb_arena 2-4,
--              mini_golf 2-4, basketball_battle 2-4
--   team       finger_soccer 2-6   (1v1, 2v2, 3v3 — two equal sides)
--   social     spy_mafia 4-8, mafia 6-12
--
-- Audience is unlimited: a talk room stores NULL speaker/spectator capacities and nx_room_join never refuses a
-- listener. What the manager controls is the *board*: nx_rooms.seats (2..32, validated against the game bounds).
--
-- New surface (all SECURITY DEFINER, server-validated, manager only where it matters):
--   nx_room_capacity(room)              -> {min_players, max_players, capacity, selected, audience, locked, is_manager}
--   nx_room_set_capacity(room, n)       -> host picks any legal capacity for this game
--   nx_room_set_locked(room, bool)      -> admission closed/open (existing members keep their seat)
--   nx_room_kick(room, user)            -> host removes a player from the room and the line-up
--   nx_room_join                        -> refuses joins on a locked room, keeps reconnects working
--   nx_room_select_players              -> cannot pick more players than the room's capacity
--   nx_room_start_room_match            -> re-validates capacity + team balance server-side
--   nx_talk_rooms()                     -> now exposes capacity next to the member count

-- ---------------------------------------------------------------- 1. authoritative bounds
create or replace function public.nx_game_bounds(p_game text, out min_seats integer, out max_seats integer)
 returns record language sql immutable as $$
  select case p_game
           when 'mafia' then 6
           when 'spy_mafia' then 4
           else 2 end,
         case p_game
           when 'finger_soccer' then 6
           when 'mafia' then 12
           when 'spy_mafia' then 8
           when 'ludo' then 4
           when 'snakes_ladders' then 4
           when 'uno' then 4
           when 'kart_racing' then 4
           when 'obstacle_race' then 4
           when 'bomb_arena' then 4
           when 'mini_golf' then 4
           when 'basketball_battle' then 4
           else 2 end
$$;

create or replace function public._nx_room_seat_limit(p_game text) returns integer
 language sql immutable as $$ select (public.nx_game_bounds(p_game)).max_seats $$;

-- ---------------------------------------------------------------- 2. schema
alter table public.nx_rooms drop constraint if exists nx_rooms_seats_check;
alter table public.nx_rooms add constraint nx_rooms_seats_check check (seats >= 2 and seats <= 32);
alter table public.nx_rooms add column if not exists join_locked boolean not null default false;
create index if not exists nx_rooms_kind_status_idx on public.nx_rooms(kind, status, updated_at desc);

-- Bring existing rooms back inside the corrected bounds (never below the players already seated).
update public.nx_rooms r
   set seats = greatest(
         (public.nx_game_bounds(coalesce(r.selected_game, r.game))).min_seats,
         least(r.seats, (public.nx_game_bounds(coalesce(r.selected_game, r.game))).max_seats))
 where r.seats is distinct from greatest(
         (public.nx_game_bounds(coalesce(r.selected_game, r.game))).min_seats,
         least(r.seats, (public.nx_game_bounds(coalesce(r.selected_game, r.game))).max_seats));

-- ---------------------------------------------------------------- 3. helpers
-- The manager of a room, in both models: talk rooms carry a nx_room_members role, game lobbies use nx_rooms.host.
create or replace function public._nx_room_can_manage(p_room uuid) returns boolean
 language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from public.nx_rooms r where r.id = p_room and r.host = auth.uid())
      or public.nx_room_member_role(p_room) = 'manager'
$$;

create or replace function public._nx_room_selected(p_room uuid) returns integer
 language sql stable security definer set search_path to 'public' as $$
  select greatest(
    (select count(*)::int from public.nx_room_game_players where room_id = p_room),
    (select count(*)::int from public.nx_room_players where room_id = p_room))
$$;

create or replace function public._nx_room_audience(p_room uuid) returns integer
 language sql stable security definer set search_path to 'public' as $$
  select greatest(
    (select count(*)::int from public.nx_room_members where room_id = p_room),
    (select count(*)::int from public.nx_room_players where room_id = p_room))
$$;

-- ---------------------------------------------------------------- 4. read the capacity
create or replace function public.nx_room_capacity(p_room uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r public.nx_rooms; b record; sel int; aud int; role_v text; g text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from public.nx_rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if r.is_private and r.host <> auth.uid() and not public.nx_in_room(r.id) and not public.nx_is_room_member(r.id) then
    raise exception 'room not visible';
  end if;
  g := coalesce(r.selected_game, r.game);
  select * into b from public.nx_game_bounds(g);
  sel := public._nx_room_selected(p_room);
  aud := public._nx_room_audience(p_room);
  role_v := public.nx_room_member_role(p_room);
  return jsonb_build_object(
    'room_id', r.id,
    'kind', r.kind,
    'game', g,
    'status', r.status,
    'min_players', greatest(2, b.min_seats),
    'max_players', b.max_seats,
    'capacity', greatest(b.min_seats, least(coalesce(r.seats, b.max_seats), b.max_seats)),
    'selected', sel,
    'audience', aud,
    'locked', coalesce(r.join_locked, false),
    'is_manager', public._nx_room_can_manage(p_room),
    'role', role_v);
end $$;

-- ---------------------------------------------------------------- 5. host sets the capacity
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
  sel := public._nx_room_selected(p_room);
  if cap < sel then raise exception '% players are already picked (remove players first)', sel; end if;
  update public.nx_rooms set seats = cap, updated_at = now() where id = p_room;
  return public.nx_room_capacity(p_room);
end $$;

-- ---------------------------------------------------------------- 6. admission lock
create or replace function public.nx_room_set_locked(p_room uuid, p_locked boolean)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  update public.nx_rooms set join_locked = coalesce(p_locked, false), updated_at = now() where id = p_room;
  return public.nx_room_capacity(p_room);
end $$;

-- ---------------------------------------------------------------- 7. host removes a player
create or replace function public.nx_room_kick(p_room uuid, p_user uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_user is null or p_user = auth.uid() then raise exception 'cannot remove yourself'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if r.status = 'playing' then raise exception 'room already started'; end if;
  if exists (select 1 from public.nx_room_members where room_id = p_room and user_id = p_user and role = 'manager') then
    raise exception 'cannot remove the manager';
  end if;
  delete from public.nx_room_game_players where room_id = p_room and user_id = p_user;
  delete from public.nx_room_players where room_id = p_room and user_id = p_user;
  delete from public.nx_room_members where room_id = p_room and user_id = p_user;
  -- keep the remaining line-up compact so seat parity (team sides) does not shift under the players
  update public.nx_rooms set selected_seats = coalesce(
      (select array_agg(seat order by seat) from public.nx_room_game_players where room_id = p_room), '{}'),
    updated_at = now() where id = p_room;
  return public.nx_room_capacity(p_room);
end $$;

-- ---------------------------------------------------------------- 8. joins honour the lock
create or replace function public.nx_room_join(p_room uuid, p_role text default 'speaker')
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); r public.nx_rooms; role_to_use text; speakers int; spectators int; seat_no int; game_limit int;
begin
  if me is null then raise exception 'not signed in'; end if;
  insert into public.profiles(id, username) values (me, coalesce(auth.jwt() -> 'user_metadata' ->> 'username', 'Pilot'))
    on conflict (id) do nothing;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status = 'closed' then raise exception 'room closed'; end if;
  if exists(select 1 from public.nx_room_members where room_id = p_room and user_id = me) then
    update public.nx_room_members set last_seen = now() where room_id = p_room and user_id = me;
    return jsonb_build_object('room_id', p_room, 'role', public.nx_room_member_role(p_room), 'rejoined', true, 'status', r.status, 'match_id', r.match_id);
  end if;
  -- Admission: a locked room keeps its reconnects (handled above) but takes nobody new.
  if coalesce(r.join_locked, false) then raise exception 'room locked'; end if;
  select count(*) filter (where role in ('manager','speaker')), count(*) filter (where role = 'spectator')
    into speakers, spectators from public.nx_room_members where room_id = p_room;
  if p_role = 'spectator' and (r.spectator_capacity is null or spectators < r.spectator_capacity) then role_to_use := 'spectator';
  elsif r.speaker_capacity is null or speakers < r.speaker_capacity then role_to_use := 'speaker';
  elsif r.spectator_capacity is null or spectators < r.spectator_capacity then role_to_use := 'spectator';
  else raise exception 'room full'; end if;
  insert into public.nx_room_members(room_id, user_id, role) values (p_room, me, role_to_use);
  -- Game lobbies (legacy flow) still auto-seat speakers, up to the room capacity and the game limit.
  if r.kind <> 'talk' and role_to_use = 'speaker' then
    game_limit := least(coalesce(r.seats, 6), public._nx_room_seat_limit(coalesce(r.selected_game, r.game)));
    select min(g) into seat_no from generate_series(0, game_limit - 1) g
     where not exists(select 1 from public.nx_room_game_players where room_id = p_room and seat = g)
       and not exists(select 1 from public.nx_room_players where room_id = p_room and seat = g);
    if seat_no is not null then
      insert into public.nx_room_game_players(room_id, user_id, seat, team) values (p_room, me, seat_no, seat_no % 2);
    end if;
  end if;
  update public.nx_rooms set updated_at = now() where id = p_room;
  return jsonb_build_object('room_id', p_room, 'role', role_to_use, 'seat', seat_no, 'status', r.status, 'match_id', r.match_id);
end $$;

-- ---------------------------------------------------------------- 9. picking respects the capacity
create or replace function public.nx_room_select_players(p_room uuid, p_users uuid[])
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i int := 0; uid uuid; g public.nx_rooms; lim int; users uuid[]; ndist int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  select * into g from public.nx_rooms where id = p_room for update;
  if g.id is null then raise exception 'room not found'; end if;
  if g.status <> 'lobby' then raise exception 'room already started'; end if;
  users := coalesce(p_users, '{}');
  select count(distinct x) into ndist from unnest(users) x;
  if cardinality(users) <> coalesce(ndist, 0) then
    raise exception 'duplicate players';
  end if;
  lim := least(coalesce(g.seats, public._nx_room_seat_limit(coalesce(g.selected_game, g.game))),
               public._nx_room_seat_limit(coalesce(g.selected_game, g.game)));
  if cardinality(users) > lim then raise exception 'this room takes at most % players', lim; end if;
  if exists(select 1 from unnest(users) u
            where not exists(select 1 from public.nx_room_members m where m.room_id = p_room and m.user_id = u)) then
    raise exception 'all players must be room members';
  end if;
  delete from public.nx_room_game_players where room_id = p_room;
  foreach uid in array users loop
    insert into public.nx_room_game_players(room_id, user_id, seat, team) values (p_room, uid, i, i % 2);
    i := i + 1;
  end loop;
  update public.nx_rooms set selected_seats = coalesce((select array_agg(seat order by seat) from public.nx_room_game_players where room_id = p_room), '{}'),
         updated_at = now() where id = p_room;
  return jsonb_build_object('selected', i, 'capacity', lim);
end $$;

-- ---------------------------------------------------------------- 10. start re-validates capacity
create or replace function public.nx_start_room_match(p_room uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms; ids uuid[]; names text[]; prefs jsonb; mid uuid; seed_value bigint; n int; b record; gm text; cap int;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status = 'playing' and r.match_id is not null then return jsonb_build_object('match_id', r.match_id, 'already', true); end if;
  gm := coalesce(r.selected_game, r.game);
  select * into b from public.nx_game_bounds(gm);
  cap := least(coalesce(r.seats, b.max_seats), b.max_seats);
  select array_agg(g.user_id order by g.seat), array_agg(coalesce(p.username, 'Pilot') order by g.seat), count(*),
         coalesce(jsonb_object_agg(g.seat::text, g.prefs), '{}'::jsonb)
    into ids, names, n, prefs
    from public.nx_room_game_players g left join public.profiles p on p.id = g.user_id where g.room_id = p_room;
  if n is null or n < greatest(2, b.min_seats) then raise exception 'need at least % selected players', greatest(2, b.min_seats); end if;
  if n > cap then raise exception 'at most % players in this room', cap; end if;
  if gm = 'finger_soccer' and n % 2 <> 0 then raise exception 'finger soccer needs an even number of players (1v1, 2v2, 3v3)'; end if;
  if exists (select 1 from unnest(ids) x group by x having count(*) > 1) then raise exception 'duplicate players'; end if;
  seed_value := floor(random() * 2147483646)::bigint + 1;
  insert into public.nx_matches(room_id, game, players, names, seed, settings)
  values (p_room, gm, ids, names, seed_value, r.settings || jsonb_build_object('room_prefs', prefs, 'room', p_room))
  returning id into mid;
  update public.nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', seed_value, 'players', n, 'capacity', cap);
end $$;

-- ---------------------------------------------------------------- 11. changing the game keeps the capacity legal
create or replace function public.nx_room_change_game(p_room uuid, p_game text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms; b record;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if not public.nx_known_game(p_game) then raise exception 'unknown game'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status <> 'lobby' then raise exception 'room already started'; end if;
  select * into b from public.nx_game_bounds(p_game);
  update public.nx_rooms
     set game = p_game, selected_game = p_game, selected_seats = '{}',
         seats = greatest(b.min_seats, least(coalesce(r.seats, b.max_seats), b.max_seats)),
         updated_at = now()
   where id = p_room;
  delete from public.nx_room_game_players where room_id = p_room;
end $$;

-- ---------------------------------------------------------------- 12. rooms list exposes capacity
drop function if exists public.nx_talk_rooms();
create or replace function public.nx_talk_rooms()
 returns table(id uuid, code text, title text, game text, status text, host uuid, host_name text, members int,
               capacity int, min_players int, max_players int, locked boolean, created_at timestamptz)
 language sql stable security definer set search_path to 'public' as $$
  select r.id, r.code, r.title, coalesce(r.selected_game, r.game), r.status, r.host, p.username,
         public._nx_room_audience(r.id),
         greatest((public.nx_game_bounds(coalesce(r.selected_game, r.game))).min_seats,
                  least(coalesce(r.seats, (public.nx_game_bounds(coalesce(r.selected_game, r.game))).max_seats),
                        (public.nx_game_bounds(coalesce(r.selected_game, r.game))).max_seats)),
         greatest(2, (public.nx_game_bounds(coalesce(r.selected_game, r.game))).min_seats),
         (public.nx_game_bounds(coalesce(r.selected_game, r.game))).max_seats,
         coalesce(r.join_locked, false),
         r.created_at
    from public.nx_rooms r left join public.profiles p on p.id = r.host
   where r.kind = 'talk' and r.status <> 'closed' and not r.is_private
     and exists(select 1 from public.nx_room_members m where m.room_id = r.id and m.last_seen > now() - interval '30 minutes')
   order by r.updated_at desc limit 60 $$;

-- ---------------------------------------------------------------- 13. privileges
revoke all on function public.nx_room_capacity(uuid), public.nx_room_set_capacity(uuid, integer),
  public.nx_room_set_locked(uuid, boolean), public.nx_room_kick(uuid, uuid) from public, anon;
grant execute on function public.nx_room_capacity(uuid), public.nx_room_set_capacity(uuid, integer),
  public.nx_room_set_locked(uuid, boolean), public.nx_room_kick(uuid, uuid) to authenticated;
grant execute on function public.nx_talk_rooms() to authenticated;
revoke execute on function public.nx_talk_rooms() from anon, public;
