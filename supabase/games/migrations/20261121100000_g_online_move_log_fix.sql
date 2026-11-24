-- ANIX PRO P0 online fix (games project).
--
-- Root cause of "room match stuck on the formation screen (waiting for the other players)" and of quick matches where
-- the two phones show different boards: 20261117350000_g_turn_authority made nx_push_move
--   * rotate nx_matches.turn_seat on EVERY non-snap move, and refuse any move whose seat is not turn_seat ('turn'),
--   * refuse every move posted more than 10 s after the previous one ('timeout').
-- The games do not post exactly one move per turn: the pre-match team / formation picks of BOTH phones, the
-- shooter's 'settled' snapshot and 'goal' after its 'shot', Ludo's roll + move, etc. So the second phone's picks were
-- refused (and after 10 s everybody's were) -> the match never started; in play the authority snapshot and goals were
-- refused -> each phone kept its own simulation and score.
--
-- The move log is an ordered, append-only input log (seq = last + 1, first writer wins); turn order is enforced by
-- the deterministic game on every phone and the result by the consensus of 20261121000000_g_pro_result_integrity.
-- This version keeps the seq + seat ownership rules, drops the per-move turn gate, and keeps turn_deadline only as an
-- activity clock (now() + 45 s on every move) that the result-consensus code reads to tell a gone player.
-- (The app already posts 'move'/'timeout' rows as kind 'system' with the real kind in move->>'_k', so it works on the
--  old function too; this migration restores the intended server behaviour.)

create or replace function public.nx_push_move(
  p_match uuid,
  p_seq integer,
  p_kind text,
  p_move jsonb,
  p_hash text,
  p_seat integer default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  m nx_matches;
  caller_seat int;
  effective_seat int;
  k text := left(coalesce(p_kind, 'move'), 16);
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  caller_seat := array_position(m.players, me) - 1;
  if caller_seat is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', false, 'reason', 'over', 'last_seq', m.last_seq);
  end if;
  if p_seq <> m.last_seq + 1 then
    return jsonb_build_object('ok', false, 'reason', 'seq', 'last_seq', m.last_seq);
  end if;
  if pg_column_size(coalesce(p_move, '{}'::jsonb)) > 16000 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;
  -- Ordinary gameplay moves are always posted for the caller's own seat; the authority may post a snapshot, a
  -- timeout or a system row (pre-match defaults for an absent side) for another seat.
  if p_seat is not null and p_seat <> caller_seat and k not in ('snap', 'timeout', 'forfeit', 'system') then
    raise exception 'seat mismatch';
  end if;
  if p_seat is not null and (p_seat < 0 or p_seat >= coalesce(array_length(m.players, 1), 0)) then
    raise exception 'bad seat';
  end if;
  effective_seat := coalesce(p_seat, caller_seat);

  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, effective_seat, me, k, coalesce(p_move, '{}'::jsonb), p_hash);

  update nx_matches
     set last_seq = p_seq,
         state_hash = coalesce(p_hash, state_hash),
         turn_seat = effective_seat,
         turn_deadline = now() + interval '45 seconds'
   where id = p_match;
  return jsonb_build_object('ok', true, 'seq', p_seq);
end;
$$;

revoke all on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Quick match: two players who tapped "quick match" at the same moment each created a lobby (nobody else was
-- waiting yet) and then waited forever in two different lobbies. The app now re-calls nx_quick every few seconds
-- while it waits; a waiting player moves into an OLDER open lobby of the same game / seats (never a newer one, so two
-- waiting players never swap into each other's lobby at the same time), and the older lobby starts when full.
create or replace function public.nx_quick(p_game text, p_seats integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); rid uuid; res jsonb; n int; r nx_rooms; mine nx_rooms;
begin
  if me is null then raise exception 'not signed in'; end if;
  -- drop silent seats from quick lobbies, close empty / stale ones
  delete from nx_room_players rp using nx_rooms x
   where x.id = rp.room_id and x.quick and x.status = 'lobby' and rp.user_id <> me and rp.last_seen < now() - interval '30 seconds';
  delete from nx_room_members m using nx_rooms x
   where x.id = m.room_id and x.quick and x.status = 'lobby'
     and not exists(select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = m.user_id);
  update nx_rooms x set status = 'closed'
   where x.status = 'lobby' and x.quick
     and (x.updated_at < now() - interval '10 minutes' or not exists(select 1 from nx_room_players rp where rp.room_id = x.id));
  -- already waiting for this game?
  select x.* into mine from nx_rooms x join nx_room_players rp on rp.room_id = x.id and rp.user_id = me
   where x.quick and x.status = 'lobby' and x.game = p_game and x.seats = p_seats limit 1;
  if mine.id is not null then
    update nx_room_players set last_seen = now() where room_id = mine.id and user_id = me;
    update nx_rooms set updated_at = now() where id = mine.id;
    select count(*) into n from nx_room_players where room_id = mine.id;
    if n >= mine.seats then
      return jsonb_build_object('room_id', mine.id, 'code', mine.code, 'rejoined', true) || nx_start_match_quick(mine.id);
    end if;
  end if;
  select x.id into rid from nx_rooms x
   where x.game = p_game and x.status = 'lobby' and x.quick and not x.is_private and x.seats = p_seats
     and (mine.id is null or (x.id <> mine.id and x.created_at < mine.created_at))
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
  return res || jsonb_build_object('moved', mine.id is not null);
end $$;

revoke all on function public.nx_quick(text, integer) from public, anon;
grant execute on function public.nx_quick(text, integer) to authenticated;

-- Cancel quick matchmaking: leave a waiting quick lobby (closes it when empty).
create or replace function public.nx_quick_cancel(p_room uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid();
begin
  if me is null then return; end if;
  delete from nx_room_players rp using nx_rooms x
   where x.id = rp.room_id and x.id = p_room and x.quick and x.status = 'lobby' and rp.user_id = me;
  delete from nx_room_members m using nx_rooms x
   where x.id = m.room_id and x.id = p_room and x.quick and x.status = 'lobby' and m.user_id = me;
  update nx_rooms x set status = 'closed'
   where x.id = p_room and x.quick and x.status = 'lobby'
     and not exists(select 1 from nx_room_players rp where rp.room_id = x.id);
end $$;
revoke all on function public.nx_quick_cancel(uuid) from public, anon;
grant execute on function public.nx_quick_cancel(uuid) to authenticated;
