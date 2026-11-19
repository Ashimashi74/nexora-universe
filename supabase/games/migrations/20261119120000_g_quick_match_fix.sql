-- Quick match hardening.
-- * Idempotent: a player already waiting in a quick lobby for the same game/seats gets that lobby back (reconnects and
--   double taps no longer leave a ghost seat behind); otherwise they leave every other lobby before joining one.
-- * No ghosts: waiting lobbies send a heartbeat (nx_lobby_ping, every few seconds from the lobby screen); seats silent
--   for 45 s are dropped from quick lobbies before pairing, and lobbies left empty close.
create or replace function public.nx_lobby_ping(p_room uuid) returns void
 language sql security definer set search_path to 'public' as $$
  update public.nx_room_players set last_seen = now() where room_id = p_room and user_id = auth.uid();
  update public.nx_rooms set updated_at = now() where id = p_room and status = 'lobby'
     and exists(select 1 from public.nx_room_players where room_id = p_room and user_id = auth.uid()); $$;
grant execute on function public.nx_lobby_ping(uuid) to authenticated;
revoke execute on function public.nx_lobby_ping(uuid) from anon, public;

create or replace function public.nx_quick(p_game text, p_seats integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); rid uuid; res jsonb; n int; r nx_rooms; mine nx_rooms;
begin
  if me is null then raise exception 'not signed in'; end if;
  -- drop silent seats from quick lobbies, close empty / stale ones
  delete from nx_room_players rp using nx_rooms x
   where x.id = rp.room_id and x.quick and x.status = 'lobby' and rp.user_id <> me and rp.last_seen < now() - interval '45 seconds';
  delete from nx_room_members m using nx_rooms x
   where x.id = m.room_id and x.quick and x.status = 'lobby'
     and not exists(select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = m.user_id);
  update nx_rooms x set status = 'closed'
   where x.status = 'lobby' and x.quick
     and (x.updated_at < now() - interval '10 minutes' or not exists(select 1 from nx_room_players rp where rp.room_id = x.id));
  -- already waiting for this game? keep that lobby (reconnect / double tap)
  select x.* into mine from nx_rooms x join nx_room_players rp on rp.room_id = x.id and rp.user_id = me
   where x.quick and x.status = 'lobby' and x.game = p_game and x.seats = p_seats limit 1;
  if mine.id is not null then
    update nx_room_players set last_seen = now() where room_id = mine.id and user_id = me;
    select count(*) into n from nx_room_players where room_id = mine.id;
    if n >= mine.seats then
      return jsonb_build_object('room_id', mine.id, 'code', mine.code, 'rejoined', true) || nx_start_match_quick(mine.id);
    end if;
  end if;
  select x.id into rid from nx_rooms x
   where x.game = p_game and x.status = 'lobby' and x.quick and not x.is_private and x.seats = p_seats
     and (mine.id is null or x.id <> mine.id)
     and not exists (select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = me)
     and (select count(*) from nx_room_players rp where rp.room_id = x.id) < x.seats
   order by x.created_at limit 1 for update skip locked;
  if rid is null then
    if mine.id is not null then
      return jsonb_build_object('room_id', mine.id, 'code', mine.code, 'seats', mine.seats, 'rejoined', true);
    end if;
    res := nx_create_room(p_game, p_seats, false, true, '{}'::jsonb);
    return res || jsonb_build_object('created', true);
  end if;
  perform _nx_leave_all(me);
  res := nx_join_room(null, rid);
  update nx_room_players set last_seen = now() where room_id = rid and user_id = me;
  select * into r from nx_rooms where id = rid;
  select count(*) into n from nx_room_players where room_id = rid;
  if n >= r.seats then
    res := res || nx_start_match_quick(rid);
  end if;
  return res;
end $$;
