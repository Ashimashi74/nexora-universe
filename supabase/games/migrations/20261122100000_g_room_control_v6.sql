-- ROOM CONTROL v6 — host controls that were still missing, plus voice/permission management.
--
-- The v5 migration gave the manager capacity, admission lock, removal and a server-validated
-- start. Three things were still impossible from the room screen, and one was impossible from
-- the protocol:
--
--   1. Transfer the room. A manager could only hand over the room by leaving it (nx_room_leave
--      promoted the longest-present member, chosen by the server, not by the host). A host who
--      wants to keep talking but let someone else run the match had no way to do it.
--   2. Close the room on purpose. Leaving was the only way to end a room, and that only closes
--      it when the *manager* leaves and nobody is left.
--   3. Give a member permission to manage voice (mic) without making them the manager.
--      nx_room_set_muted only accepted the literal role 'manager'.
--
-- Everything below is SECURITY DEFINER, re-checks the caller with _nx_room_can_manage (the
-- total boolean from v5 fix) and is granted to authenticated only. No client flag can widen
-- any of it: the server decides who may do what, the UI only mirrors it.
--
-- Capacity itself is unchanged and stays host-controlled per game: nx_room_set_capacity
-- (2..32 room-wide, clamped per game by nx_game_bounds, even sides for team games). The
-- audience (speakers + listeners) is unlimited: speaker_capacity / spectator_capacity stay
-- NULL and nx_room_join never refuses a listener.

-- ---------------------------------------------------------------- 1. transfer host
create or replace function public.nx_room_transfer_host(p_room uuid, p_user uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms; was uuid := auth.uid();
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_user is null or p_user = was then raise exception 'pick another member'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if not exists (select 1 from public.nx_room_members m where m.room_id = p_room and m.user_id = p_user) then
    raise exception 'member not found';
  end if;
  -- Exactly two roles exist ('manager' is a member role); the old manager keeps their seat and
  -- speaking rights as a plain speaker so the conversation is not interrupted.
  update public.nx_room_members set role = 'manager' where room_id = p_room and user_id = p_user;
  update public.nx_room_members set role = 'speaker' where room_id = p_room and user_id = was and role = 'manager';
  update public.nx_rooms set host = p_user, updated_at = now() where id = p_room;
  return jsonb_build_object('room_id', p_room, 'host', p_user, 'is_manager', false);
end $$;

revoke all on function public.nx_room_transfer_host(uuid, uuid) from public, anon;
grant execute on function public.nx_room_transfer_host(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------- 2. close the room
create or replace function public.nx_room_close(p_room uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if r.status = 'playing' then raise exception 'a match is running'; end if;
  update public.nx_rooms set status = 'closed', updated_at = now() where id = p_room;
  -- Members stay until they leave so the client can show "the host closed this room" instead of
  -- a silent 404 on the next poll; a closed room accepts nobody new (nx_room_join refuses it).
  return jsonb_build_object('room_id', p_room, 'status', 'closed');
end $$;

revoke all on function public.nx_room_close(uuid) from public, anon;
grant execute on function public.nx_room_close(uuid) to authenticated;

-- ---------------------------------------------------------------- 3. voice management for members
-- Muting/role changes are room-wide voice controls, not match controls, so any member the
-- manager promoted (a future "voice moderator") is allowed in addition to the manager.
create or replace function public.nx_room_set_muted(p_room uuid, p_user uuid, p_muted boolean)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_user = auth.uid() then raise exception 'use your own mic control'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  if not exists (select 1 from public.nx_room_members m where m.room_id = p_room and m.user_id = p_user) then
    raise exception 'member not found';
  end if;
  update public.nx_room_members set muted = coalesce(p_muted, false) where room_id = p_room and user_id = p_user;
end $$;

create or replace function public.nx_room_set_role(p_room uuid, p_user uuid, p_role text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare r public.nx_rooms;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_role not in ('speaker','spectator') then raise exception 'bad role'; end if;
  if not public._nx_room_can_manage(p_room) then raise exception 'manager only'; end if;
  select * into r from public.nx_rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  -- The manager is the manager: demoting yourself would leave the room without one.
  if exists (select 1 from public.nx_room_members m where m.room_id = p_room and m.user_id = p_user and m.role = 'manager') then
    raise exception 'cannot change the manager role';
  end if;
  update public.nx_room_members set role = p_role, last_seen = now()
   where room_id = p_room and user_id = p_user;
  if not found then raise exception 'member not found'; end if;
end $$;

revoke all on function public.nx_room_set_muted(uuid, uuid, boolean),
  public.nx_room_set_role(uuid, uuid, text) from public, anon;
grant execute on function public.nx_room_set_muted(uuid, uuid, boolean),
  public.nx_room_set_role(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------- 4. joins report the closed state
-- nx_room_join already refused 'closed' rooms; it now says so explicitly to a *member* too, so a
-- phone that reconnects after the host closed the room shows the right message instead of
-- rejoining a dead room.
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
    return jsonb_build_object('room_id', p_room, 'role', public.nx_room_member_role(p_room), 'rejoined', true,
                              'status', r.status, 'match_id', r.match_id);
  end if;
  if coalesce(r.join_locked, false) then raise exception 'room locked'; end if;
  select count(*) filter (where role in ('manager','speaker')), count(*) filter (where role = 'spectator')
    into speakers, spectators from public.nx_room_members where room_id = p_room;
  -- Unlimited audience: only an explicitly capped room can refuse a listener.
  if p_role = 'spectator' and (r.spectator_capacity is null or spectators < r.spectator_capacity) then role_to_use := 'spectator';
  elsif r.speaker_capacity is null or speakers < r.speaker_capacity then role_to_use := 'speaker';
  elsif r.spectator_capacity is null or spectators < r.spectator_capacity then role_to_use := 'spectator';
  else raise exception 'room full'; end if;
  insert into public.nx_room_members(room_id, user_id, role) values (p_room, me, role_to_use);
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

revoke all on function public.nx_room_join(uuid, text) from public, anon;
grant execute on function public.nx_room_join(uuid, text) to authenticated;
