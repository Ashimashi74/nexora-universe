-- ROOMS centred on conversation (games project).
-- * FIX: room members / game players / messages referenced auth.users of THIS project, which is always empty
--   (users sign in on the auth project) -> every insert failed. They now reference the profiles mirror.
-- * Unlimited speakers and listeners (capacity NULL = unlimited). Mafia and party games up to 12, team games up to 6.
-- * Talk rooms: nx_room_open(title) creates a room without seating anyone; the manager picks a game, ticks the
--   players (nx_room_select_players) and starts it (nx_start_room_match). Each picked player stores pre-game choices
--   (team / formation) with nx_room_set_prefs; the manager stores field / ball in settings with nx_room_set_settings.
--   The match carries settings.room_prefs = {seat: prefs}. After the match the room goes back to 'lobby'.

alter table public.nx_room_members drop constraint if exists nx_room_members_user_id_fkey;
alter table public.nx_room_game_players drop constraint if exists nx_room_game_players_user_id_fkey;
alter table public.nx_room_messages drop constraint if exists nx_room_messages_author_fkey;
alter table public.nx_room_members add constraint nx_room_members_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
alter table public.nx_room_game_players add constraint nx_room_game_players_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
alter table public.nx_room_messages add constraint nx_room_messages_author_fkey foreign key (author) references public.profiles(id) on delete cascade;

alter table public.nx_rooms alter column speaker_capacity drop default, alter column spectator_capacity drop default,
  alter column speaker_capacity drop not null, alter column spectator_capacity drop not null;
alter table public.nx_rooms add column if not exists title text, add column if not exists kind text not null default 'game';
update public.nx_rooms set speaker_capacity = null, spectator_capacity = null;
alter table public.nx_room_game_players add column if not exists prefs jsonb not null default '{}'::jsonb;
create index if not exists nx_room_messages_room_time on public.nx_room_messages(room_id, created_at desc);

create or replace function public.nx_game_bounds(p_game text, out min_seats integer, out max_seats integer)
 returns record language sql immutable as $$
  select case p_game when 'ludo' then 2 when 'snakes_ladders' then 2 when 'uno' then 2 when 'quiz' then 2
                     when 'mafia' then 6 when 'spy_mafia' then 3 else 2 end,
         case p_game when 'ludo' then 4 when 'snakes_ladders' then 4 when 'uno' then 4 when 'quiz' then 21
                     when 'mafia' then 12 when 'spy_mafia' then 12
                     when 'kart_racing' then 4 when 'obstacle_race' then 4 when 'bomb_arena' then 4
                     when 'mini_golf' then 4 when 'stickman_arena' then 4
                     when 'ludo_battle' then 4 when 'finger_soccer' then 6 when 'carrom' then 6 else 2 end $$;

create or replace function public._nx_room_seat_limit(p_game text) returns integer language sql immutable as $$
  select (public.nx_game_bounds(p_game)).max_seats $$;

alter table public.nx_rooms drop constraint if exists nx_rooms_seats_check;
alter table public.nx_rooms add constraint nx_rooms_seats_check check (seats >= 2 and seats <= 21);

-- Talk room: nobody is seated; manager = creator. Unlimited audience.
create or replace function public.nx_room_open(p_title text default null, p_private boolean default false, p_game text default 'finger_soccer')
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); rid uuid; c text; g text := coalesce(nullif(p_game, ''), 'finger_soccer');
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.nx_known_game(g) then raise exception 'unknown game'; end if;
  insert into public.profiles(id, username) values (me, coalesce(auth.jwt() -> 'user_metadata' ->> 'username', 'Pilot'))
    on conflict (id) do nothing;
  c := public.nx_gen_code();
  insert into public.nx_rooms(code, game, host, seats, is_private, quick, settings, selected_game, title, kind,
                              speaker_capacity, spectator_capacity)
  values (c, g, me, greatest(2, (public.nx_game_bounds(g)).max_seats), coalesce(p_private, false), false, '{}'::jsonb, g,
          nullif(left(btrim(coalesce(p_title, '')), 60), ''), 'talk', null, null)
  returning id into rid;
  insert into public.nx_room_members(room_id, user_id, role) values (rid, me, 'manager');
  return jsonb_build_object('room_id', rid, 'code', c);
end $$;

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
  select count(*) filter (where role in ('manager','speaker')), count(*) filter (where role = 'spectator')
    into speakers, spectators from public.nx_room_members where room_id = p_room;
  if p_role = 'spectator' and (r.spectator_capacity is null or spectators < r.spectator_capacity) then role_to_use := 'spectator';
  elsif r.speaker_capacity is null or speakers < r.speaker_capacity then role_to_use := 'speaker';
  elsif r.spectator_capacity is null or spectators < r.spectator_capacity then role_to_use := 'spectator';
  else raise exception 'room full'; end if;
  insert into public.nx_room_members(room_id, user_id, role) values (p_room, me, role_to_use);
  -- Game rooms (legacy lobby flow) still auto-seat speakers; talk rooms seat only the players the manager picks.
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

create or replace function public.nx_room_set_role(p_room uuid, p_user uuid, p_role text)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  if p_role not in ('speaker','spectator') then raise exception 'bad role'; end if;
  update public.nx_room_members set role = p_role, last_seen = now() where room_id = p_room and user_id = p_user and p_user <> auth.uid();
  if not found then raise exception 'member not found'; end if;
end $$;

create or replace function public.nx_room_set_muted(p_room uuid, p_user uuid, p_muted boolean)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  update public.nx_room_members set muted = coalesce(p_muted, false) where room_id = p_room and user_id = p_user;
end $$;

create or replace function public.nx_room_change_game(p_room uuid, p_game text)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  if not public.nx_known_game(p_game) then raise exception 'unknown game'; end if;
  update public.nx_rooms set game = p_game, selected_game = p_game, selected_seats = '{}',
         seats = greatest(2, (public.nx_game_bounds(p_game)).max_seats), updated_at = now()
   where id = p_room and status = 'lobby';
  if not found then raise exception 'room already started'; end if;
  delete from public.nx_room_game_players where room_id = p_room;
end $$;

create or replace function public.nx_room_select_players(p_room uuid, p_users uuid[])
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i int := 0; uid uuid; g public.nx_rooms; lim int;
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  select * into g from public.nx_rooms where id = p_room for update;
  if g.id is null then raise exception 'room not found'; end if;
  if g.status <> 'lobby' then raise exception 'room already started'; end if;
  lim := public._nx_room_seat_limit(coalesce(g.selected_game, g.game));
  if cardinality(coalesce(p_users, '{}')) > lim then raise exception 'game supports at most % players', lim; end if;
  if exists(select 1 from unnest(coalesce(p_users, '{}')) u
            where not exists(select 1 from public.nx_room_members m where m.room_id = p_room and m.user_id = u)) then
    raise exception 'all players must be room members';
  end if;
  delete from public.nx_room_game_players where room_id = p_room;
  foreach uid in array coalesce(p_users, '{}') loop
    insert into public.nx_room_game_players(room_id, user_id, seat, team) values (p_room, uid, i, i % 2);
    i := i + 1;
  end loop;
  update public.nx_rooms set selected_seats = coalesce((select array_agg(seat order by seat) from public.nx_room_game_players where room_id = p_room), '{}'),
         updated_at = now() where id = p_room;
  return jsonb_build_object('selected', i);
end $$;

-- A picked player's own pre-game choices (team id, formation...).
create or replace function public.nx_room_set_prefs(p_room uuid, p_prefs jsonb)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if pg_column_size(coalesce(p_prefs, '{}'::jsonb)) > 2000 then raise exception 'prefs too large'; end if;
  update public.nx_room_game_players set prefs = coalesce(p_prefs, '{}'::jsonb), ready = true
   where room_id = p_room and user_id = auth.uid();
  if not found then raise exception 'not selected'; end if;
  update public.nx_rooms set updated_at = now() where id = p_room;
end $$;

-- Manager's match settings (field, ball, match length...), merged into the room settings.
create or replace function public.nx_room_set_settings(p_room uuid, p_settings jsonb)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  if pg_column_size(coalesce(p_settings, '{}'::jsonb)) > 4000 then raise exception 'settings too large'; end if;
  update public.nx_rooms set settings = settings || coalesce(p_settings, '{}'::jsonb), updated_at = now()
   where id = p_room and status = 'lobby';
end $$;

create or replace function public.nx_start_room_match(p_room uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms; ids uuid[]; names text[]; prefs jsonb; mid uuid; seed_value bigint; n int; b record; gm text;
begin
  if public.nx_room_member_role(p_room) is distinct from 'manager' then raise exception 'manager only'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status = 'playing' and r.match_id is not null then return jsonb_build_object('match_id', r.match_id, 'already', true); end if;
  gm := coalesce(r.selected_game, r.game);
  select * into b from public.nx_game_bounds(gm);
  select array_agg(g.user_id order by g.seat), array_agg(coalesce(p.username, 'Pilot') order by g.seat), count(*),
         coalesce(jsonb_object_agg(g.seat::text, g.prefs), '{}'::jsonb)
    into ids, names, n, prefs
    from public.nx_room_game_players g left join public.profiles p on p.id = g.user_id where g.room_id = p_room;
  if n is null or n < greatest(2, b.min_seats) then raise exception 'need at least % selected players', greatest(2, b.min_seats); end if;
  if n > public._nx_room_seat_limit(gm) then raise exception 'at most % players', public._nx_room_seat_limit(gm); end if;
  if gm = 'finger_soccer' and n % 2 = 1 then raise exception 'finger soccer needs an even number of players (1v1, 2v2, 3v3)'; end if;
  seed_value := floor(random() * 2147483646)::bigint + 1;
  insert into public.nx_matches(room_id, game, players, names, seed, settings)
  values (p_room, gm, ids, names, seed_value, r.settings || jsonb_build_object('room_prefs', prefs, 'room', p_room))
  returning id into mid;
  update public.nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', seed_value, 'players', n);
end $$;

-- Leaving a talk room: the manager role passes to the longest-present member; an empty talk room closes.
create or replace function public.nx_room_leave(p_room uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); was text; nxt uuid; r public.nx_rooms;
begin
  select role into was from public.nx_room_members where room_id = p_room and user_id = me;
  delete from public.nx_room_game_players where room_id = p_room and user_id = me and
    not exists(select 1 from public.nx_rooms where id = p_room and status = 'playing');
  delete from public.nx_room_players where room_id = p_room and user_id = me;
  delete from public.nx_room_members where room_id = p_room and user_id = me;
  select * into r from public.nx_rooms where id = p_room;
  if was = 'manager' then
    select user_id into nxt from public.nx_room_members where room_id = p_room order by joined_at limit 1;
    if nxt is not null then
      update public.nx_room_members set role = 'manager' where room_id = p_room and user_id = nxt;
      update public.nx_rooms set host = nxt where id = p_room;
    end if;
  end if;
  if r.kind = 'talk' and not exists(select 1 from public.nx_room_members where room_id = p_room) then
    update public.nx_rooms set status = 'closed', updated_at = now() where id = p_room;
  else
    update public.nx_rooms set updated_at = now() where id = p_room;
  end if;
end $$;

-- Public talk rooms with live member counts (for the rooms list).
create or replace function public.nx_talk_rooms()
 returns table(id uuid, code text, title text, game text, status text, host uuid, host_name text, members int, created_at timestamptz)
 language sql stable security definer set search_path to 'public' as $$
  select r.id, r.code, r.title, coalesce(r.selected_game, r.game), r.status, r.host, p.username,
         (select count(*)::int from public.nx_room_members m where m.room_id = r.id), r.created_at
    from public.nx_rooms r left join public.profiles p on p.id = r.host
   where r.kind = 'talk' and r.status <> 'closed' and not r.is_private
     and exists(select 1 from public.nx_room_members m where m.room_id = r.id and m.last_seen > now() - interval '30 minutes')
   order by r.updated_at desc limit 60 $$;

-- Presence ping (keeps the room listed while someone is in it).
create or replace function public.nx_room_ping(p_room uuid) returns void language sql security definer set search_path to 'public' as $$
  update public.nx_room_members set last_seen = now() where room_id = p_room and user_id = auth.uid() $$;

grant execute on function public.nx_room_open(text, boolean, text), public.nx_room_set_prefs(uuid, jsonb),
  public.nx_room_set_settings(uuid, jsonb), public.nx_talk_rooms(), public.nx_room_ping(uuid),
  public.nx_room_set_muted(uuid, uuid, boolean) to authenticated;
revoke execute on function public.nx_room_open(text, boolean, text), public.nx_room_set_prefs(uuid, jsonb),
  public.nx_room_set_settings(uuid, jsonb), public.nx_talk_rooms(), public.nx_room_ping(uuid),
  public.nx_room_set_muted(uuid, uuid, boolean) from anon, public;

-- FIX: the members read policy queried nx_room_members from inside its own policy (infinite recursion -> every
-- read of members / messages / picked players failed). Membership is now checked by a SECURITY DEFINER helper.
create or replace function public.nx_is_room_member(p_room uuid) returns boolean
 language sql stable security definer set search_path to 'public' as $$
  select exists(select 1 from public.nx_room_members where room_id = p_room and user_id = auth.uid()) $$;
grant execute on function public.nx_is_room_member(uuid) to authenticated;
drop policy if exists nx_room_members_read on public.nx_room_members;
create policy nx_room_members_read on public.nx_room_members for select to authenticated using (public.nx_is_room_member(room_id));
drop policy if exists nx_room_players_read on public.nx_room_game_players;
create policy nx_room_players_read on public.nx_room_game_players for select to authenticated using (public.nx_is_room_member(room_id));
drop policy if exists nx_room_messages_read on public.nx_room_messages;
create policy nx_room_messages_read on public.nx_room_messages for select to authenticated using (public.nx_is_room_member(room_id) and not deleted);
