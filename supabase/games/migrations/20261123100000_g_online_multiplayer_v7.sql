-- ONLINE MULTIPLAYER v7 (games project). Forward-only, idempotent (create or replace / if not exists), no data loss.
--
-- Fixes, each traced to a real failure in the online flow:
--
--  1. Matchmaking races (nx_quick / nx_quick_cancel). Two callers could pick each other's lobbies at the same time;
--     a player moving out of its own lobby while a third player was joining it got the third player's freshly
--     started match FORFEITED by _nx_leave_all -> nx_leave_room (it re-read the room as 'playing'). Every quick-match
--     call for one (game, seats) bucket now runs under a transaction advisory lock, so pairing is serialized.
--     _nx_leave_all only leaves rooms that are still 'lobby' under a row lock (never forfeits a match as a side effect).
--  2. Quick match with an out-of-range seat count (old builds / bad defaults): nx_create_room clamped the seats but
--     nx_quick looked up "my lobby" with the raw value, so every heartbeat opened a brand-new lobby and the player
--     never paired. Seats are now normalized exactly like nx_create_room (and finger_soccer kept even).
--  3. Cancel vs start race: a player who backed out of the queue in the same instant the lobby filled left the others
--     in a match with a ghost (40-90 s until the absence forfeit). nx_quick_cancel now abandons a quick match that is
--     younger than 20 s when the canceller has not posted a single move (status 'abandoned', no rewards).
--  4. Absent host never forfeited -> turn never advanced. nx_forfeit only let SEAT 0 forfeit an absent seat, but the
--     app's authority is the lowest CONNECTED seat; when seat 0 dropped, seat 1 got 'authority only' and the match
--     hung on seat 0's turn forever. Any active player may now forfeit another seat that the SERVER sees as absent
--     (no heartbeat for 25 s, no move for 30 s, no result report, match older than 30 s). Duplicate forfeits of a
--     seat are ignored. When forfeits leave exactly one seat, the server ends the match for every player count
--     (was: only 2-player matches).
--  5. Seat ownership was not enforced: the app posts ordinary moves as kind 'system' (real kind in move->>'_k'), and
--     'system' / 'forfeit' rows were accepted for ANY seat, so a phone could post moves - or a forfeit - for its
--     opponent. nx_push_move now validates the real kind: 'move' and 'forfeit' only for the caller's own seat
--     (answer {ok:false, reason:'seat'}, no exception), snapshots / timeouts / genuine system rows may still be posted
--     for another seat by the authority. A seat that has forfeited cannot keep posting ({reason:'forfeited'}).
--  6. Match heartbeat: nx_match_ping(match) stores a per-player last_seen (nx_match_presence), used by 4 and by the
--     result consensus' "the others are gone" rule (a player still pinging is never treated as gone).
--  7. Quick rooms after the match: the room went back to 'lobby' with both seats still filled, so the next heartbeat's
--     nx_quick saw a full lobby and silently started an unwanted rematch. Finished quick rooms now close; regular
--     rooms still return to the lobby for a rematch.

-- ------------------------------------------------------------------------------------------------ 6. heartbeat
create table if not exists public.nx_match_presence (
  match_id uuid not null,
  user_id uuid not null,
  last_seen timestamptz not null default now(),
  primary key (match_id, user_id)
);
alter table public.nx_match_presence enable row level security;
revoke all on table public.nx_match_presence from public, anon, authenticated;
grant all on table public.nx_match_presence to service_role;

create or replace function public.nx_match_ping(p_match uuid)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); m nx_matches;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from nx_matches where id = p_match;
  if m.id is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not (me = any(m.players)) then return jsonb_build_object('ok', false, 'reason', 'not_player'); end if;
  if m.status = 'playing' then
    insert into nx_match_presence(match_id, user_id, last_seen) values (p_match, me, now())
    on conflict (match_id, user_id) do update set last_seen = excluded.last_seen;
  end if;
  return jsonb_build_object('ok', true, 'status', m.status, 'last_seq', m.last_seq);
end $$;
revoke all on function public.nx_match_ping(uuid) from public, anon;
grant execute on function public.nx_match_ping(uuid) to authenticated, service_role;

-- Seats that have a forfeit row.
create or replace function public._nx_forfeited_seats(p_match uuid)
 returns int[] language sql stable security definer set search_path to 'public' as $$
  select coalesce(array_agg(distinct coalesce((mv.move ->> 'seat')::int, mv.seat)), '{}'::int[])
    from public.nx_match_moves mv where mv.match_id = p_match and mv.kind = 'forfeit'
$$;
revoke all on function public._nx_forfeited_seats(uuid) from public, anon, authenticated;
grant execute on function public._nx_forfeited_seats(uuid) to service_role;

-- True while the player is visibly still in the match (heartbeat or a move recently).
create or replace function public._nx_player_active(p_match uuid, p_user uuid, p_ping_sec int default 25, p_move_sec int default 30)
 returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from public.nx_match_presence p
                  where p.match_id = p_match and p.user_id = p_user
                    and p.last_seen > now() - make_interval(secs => p_ping_sec))
      or exists (select 1 from public.nx_match_moves mv
                  where mv.match_id = p_match and mv.by_user = p_user
                    and mv.created_at > now() - make_interval(secs => p_move_sec))
$$;
revoke all on function public._nx_player_active(uuid, uuid, int, int) from public, anon, authenticated;
grant execute on function public._nx_player_active(uuid, uuid, int, int) to service_role;

-- ------------------------------------------------------------------------------------------------ 7. room after a match
create or replace function public._nx_room_after_match(p_room uuid, p_match uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if p_room is null then return; end if;
  update nx_rooms set status = case when quick then 'closed' else 'lobby' end, updated_at = now()
   where id = p_room and match_id = p_match and status = 'playing';
  update nx_room_players set ready = false where room_id = p_room and seat > 0;
end $$;
revoke all on function public._nx_room_after_match(uuid, uuid) from public, anon, authenticated;
grant execute on function public._nx_room_after_match(uuid, uuid) to service_role;

create or replace function public.nx_finish_match_as(p_match uuid, p_winners integer[], p_loser integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare m nx_matches;
begin
  update nx_matches set status = 'finished', winner_seats = p_winners, reason = 'forfeit:' || p_loser, ended_at = now()
   where id = p_match and status = 'playing' returning * into m;
  if m.id is null then return jsonb_build_object('ok', false); end if;
  perform _nx_apply_result(m, p_winners, null);
  perform _nx_room_after_match(m.room_id, m.id);
  return jsonb_build_object('ok', true, 'winners', p_winners, 'forfeit', p_loser);
end $$;
revoke all on function public.nx_finish_match_as(uuid, integer[], integer) from public, anon, authenticated;
grant execute on function public.nx_finish_match_as(uuid, integer[], integer) to service_role;

-- ------------------------------------------------------------------------------------------------ 1. leave lobbies only
create or replace function public._nx_leave_all(me uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  for r in select rp.room_id from nx_room_players rp join nx_rooms x on x.id = rp.room_id
            where rp.user_id = me and x.status = 'lobby' loop
    -- re-check under the row lock: a room that started meanwhile is left alone (never forfeit as a side effect)
    perform 1 from nx_rooms where id = r.room_id and status = 'lobby' for update;
    if found then
      perform nx_leave_room(r.room_id);
    end if;
  end loop;
end $$;
revoke all on function public._nx_leave_all(uuid) from public, anon, authenticated;
grant execute on function public._nx_leave_all(uuid) to service_role;

-- Normalized quick-match seat count (same clamp as nx_create_room; team games keep two equal sides).
create or replace function public._nx_quick_seats(p_game text, p_seats integer)
 returns integer language plpgsql immutable as $$
declare b record; s int;
begin
  select * into b from public.nx_game_bounds(p_game);
  s := greatest(b.min_seats, least(coalesce(p_seats, b.min_seats), b.max_seats));
  if p_game = 'finger_soccer' and s % 2 <> 0 then
    s := case when s + 1 <= b.max_seats then s + 1 else s - 1 end;
  end if;
  return s;
end $$;

create or replace function public._nx_quick_lock(p_game text, p_seats integer)
 returns void language sql volatile as $$
  select pg_advisory_xact_lock(hashtext('nx_quick:' || coalesce(p_game, '') || ':' || coalesce(p_seats, 0)))
$$;
revoke all on function public._nx_quick_lock(text, integer) from public, anon, authenticated;
grant execute on function public._nx_quick_lock(text, integer) to service_role;

-- ------------------------------------------------------------------------------------------------ 1-2. quick match
create or replace function public.nx_quick(p_game text, p_seats integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); rid uuid; res jsonb; n int; r nx_rooms; mine nx_rooms; s int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.nx_known_game(p_game) then raise exception 'unknown game'; end if;
  s := public._nx_quick_seats(p_game, p_seats);
  perform public._nx_quick_lock(p_game, s);

  -- drop silent seats from this bucket's waiting lobbies, close empty / stale ones
  delete from nx_room_game_players gp using nx_rooms x, nx_room_players rp
   where x.id = gp.room_id and rp.room_id = x.id and rp.user_id = gp.user_id
     and x.quick and x.status = 'lobby' and x.game = p_game and x.seats = s
     and rp.user_id <> me and rp.last_seen < now() - interval '45 seconds';
  delete from nx_room_players rp using nx_rooms x
   where x.id = rp.room_id and x.quick and x.status = 'lobby' and x.game = p_game and x.seats = s
     and rp.user_id <> me and rp.last_seen < now() - interval '45 seconds';
  delete from nx_room_members m using nx_rooms x
   where x.id = m.room_id and x.quick and x.status = 'lobby' and x.game = p_game and x.seats = s
     and not exists(select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = m.user_id);
  update nx_rooms x set status = 'closed', updated_at = now()
   where x.status = 'lobby' and x.quick and x.game = p_game and x.seats = s
     and (x.updated_at < now() - interval '10 minutes' or not exists(select 1 from nx_room_players rp where rp.room_id = x.id));

  -- already waiting in this bucket? keep that lobby (reconnect / double tap / heartbeat)
  select x.* into mine from nx_rooms x join nx_room_players rp on rp.room_id = x.id and rp.user_id = me
   where x.quick and x.status = 'lobby' and x.game = p_game and x.seats = s
   order by x.created_at limit 1;
  if mine.id is not null then
    update nx_room_players set last_seen = now() where room_id = mine.id and user_id = me;
    update nx_rooms set updated_at = now() where id = mine.id;
    select count(*) into n from nx_room_players where room_id = mine.id;
    if n >= mine.seats then
      return jsonb_build_object('room_id', mine.id, 'code', mine.code, 'seats', mine.seats, 'rejoined', true)
             || nx_start_match_quick(mine.id);
    end if;
  end if;

  -- an OLDER open lobby of the same bucket (a waiting player only ever moves into an older lobby, so two waiting
  -- players never swap into each other's lobby)
  select x.id into rid from nx_rooms x
   where x.game = p_game and x.status = 'lobby' and x.quick and not x.is_private and x.seats = s
     and (mine.id is null or (x.id <> mine.id and x.created_at < mine.created_at))
     and not exists (select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = me)
     and (select count(*) from nx_room_players rp where rp.room_id = x.id) < x.seats
   order by x.created_at limit 1 for update;
  if rid is null then
    if mine.id is not null then
      return jsonb_build_object('room_id', mine.id, 'code', mine.code, 'seats', mine.seats, 'rejoined', true);
    end if;
    res := nx_create_room(p_game, s, false, true, '{}'::jsonb);
    return res || jsonb_build_object('created', true);
  end if;

  res := nx_join_room(null, rid);           -- leaves every other lobby first (_nx_leave_all, lobby-only)
  update nx_room_players set last_seen = now() where room_id = rid and user_id = me;
  select * into r from nx_rooms where id = rid;
  select count(*) into n from nx_room_players where room_id = rid;
  if n >= r.seats then
    res := res || nx_start_match_quick(rid);
  end if;
  return res || jsonb_build_object('seats', r.seats, 'moved', mine.id is not null);
end $$;
revoke all on function public.nx_quick(text, integer) from public, anon;
grant execute on function public.nx_quick(text, integer) to authenticated;

-- ------------------------------------------------------------------------------------------------ 3. cancel
create or replace function public.nx_quick_cancel(p_room uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); r nx_rooms; m nx_matches;
begin
  if me is null then return; end if;
  select * into r from nx_rooms where id = p_room;
  if r.id is null or not r.quick then return; end if;
  perform public._nx_quick_lock(r.game, r.seats);
  select * into r from nx_rooms where id = p_room for update;
  if r.status = 'lobby' then
    delete from nx_room_game_players where room_id = p_room and user_id = me;
    delete from nx_room_players where room_id = p_room and user_id = me;
    delete from nx_room_members where room_id = p_room and user_id = me;
    if not exists(select 1 from nx_room_players rp where rp.room_id = p_room) then
      update nx_rooms set status = 'closed', updated_at = now() where id = p_room;
    elsif r.host = me then
      update nx_rooms set host = (select user_id from nx_room_players where room_id = p_room order by seat limit 1),
                          updated_at = now()
       where id = p_room;
    end if;
  elsif r.status = 'playing' and r.match_id is not null then
    -- the lobby filled in the same instant this player backed out: abandon the brand-new match (no rewards) so the
    -- others go back to matchmaking instead of waiting for an absence forfeit
    select * into m from nx_matches where id = r.match_id for update;
    if m.id is not null and m.status = 'playing' and me = any(m.players)
       and m.started_at > now() - interval '20 seconds'
       and not exists (select 1 from nx_match_moves mv where mv.match_id = m.id and mv.by_user = me) then
      update nx_matches set status = 'abandoned', winner_seats = null, reason = 'abandoned', ended_at = now()
       where id = m.id;
      update nx_rooms set status = 'closed', updated_at = now() where id = r.id;
    end if;
  end if;
end $$;
revoke all on function public.nx_quick_cancel(uuid) from public, anon;
grant execute on function public.nx_quick_cancel(uuid) to authenticated;

-- ------------------------------------------------------------------------------------------------ 4. forfeit
create or replace function public.nx_forfeit(p_match uuid, p_seat integer default null)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); m nx_matches; s int; caller int; n int; gone int[]; alive int[];
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null or m.status <> 'playing' then return jsonb_build_object('ok', false, 'reason', 'over'); end if;
  caller := array_position(m.players, me) - 1;
  if caller is null then raise exception 'not a player'; end if;
  n := coalesce(array_length(m.players, 1), 0);
  gone := public._nx_forfeited_seats(p_match);
  s := caller;
  if p_seat is not null and p_seat <> caller then
    -- forfeiting ANOTHER seat: only an active player, only a seat the server also sees as gone
    if p_seat < 0 or p_seat >= n then return jsonb_build_object('ok', false, 'reason', 'bad_seat'); end if;
    if caller = any(gone) then return jsonb_build_object('ok', false, 'reason', 'forfeited'); end if;
    if m.started_at > now() - interval '30 seconds' then
      return jsonb_build_object('ok', false, 'reason', 'too_early');
    end if;
    if exists (select 1 from nx_match_reports r where r.match_id = p_match and r.user_id = m.players[p_seat + 1]) then
      return jsonb_build_object('ok', false, 'reason', 'reported');
    end if;
    if public._nx_player_active(p_match, m.players[p_seat + 1], 25, 30) then
      return jsonb_build_object('ok', false, 'reason', 'active');
    end if;
    s := p_seat;
  end if;
  if s = any(gone) then
    return jsonb_build_object('ok', true, 'seat', s, 'already', true);
  end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move)
  values (p_match, m.last_seq + 1, s, me, 'forfeit', jsonb_build_object('seat', s));
  update nx_matches set last_seq = m.last_seq + 1 where id = p_match;
  -- lone survivor (any player count): the match ends for everyone
  select coalesce(array_agg(g), '{}'::int[]) into alive
    from generate_series(0, n - 1) g where not (g = any(gone)) and g <> s;
  if coalesce(array_length(alive, 1), 0) = 1 then
    return nx_finish_match_as(p_match, alive, s);
  elsif coalesce(array_length(alive, 1), 0) = 0 then
    update nx_matches set status = 'abandoned', reason = 'abandoned', ended_at = now() where id = p_match;
    perform _nx_room_after_match(m.room_id, m.id);
  end if;
  return jsonb_build_object('ok', true, 'seat', s);
end $$;
revoke all on function public.nx_forfeit(uuid, integer) from public, anon, authenticated;
grant execute on function public.nx_forfeit(uuid, integer) to authenticated, service_role;

-- ------------------------------------------------------------------------------------------------ 5. move log
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
  n int;
  k text := left(coalesce(p_kind, 'move'), 16);
  vk text;           -- the real kind (app wraps 'move' / 'timeout' as 'system' with move->>'_k')
  gone int[];
  alive int[];
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
  n := coalesce(array_length(m.players, 1), 0);
  if p_seat is not null and (p_seat < 0 or p_seat >= n) then
    return jsonb_build_object('ok', false, 'reason', 'bad_seat');
  end if;
  effective_seat := coalesce(p_seat, caller_seat);
  vk := case when k = 'system' and jsonb_typeof(p_move) = 'object' and (p_move ? '_k')
             then left(p_move ->> '_k', 16) else k end;

  gone := public._nx_forfeited_seats(p_match);
  if caller_seat = any(gone) and vk <> 'forfeit' then
    return jsonb_build_object('ok', false, 'reason', 'forfeited', 'last_seq', m.last_seq);
  end if;
  -- seat ownership: gameplay moves and forfeits only for the caller's own seat; the authority may post a snapshot,
  -- a timeout or a genuine system row (pre-match default for an absent side) for another seat
  if effective_seat <> caller_seat and vk not in ('snap', 'timeout', 'system') then
    return jsonb_build_object('ok', false, 'reason', 'seat', 'last_seq', m.last_seq);
  end if;
  if vk = 'forfeit' and effective_seat = any(gone) then
    return jsonb_build_object('ok', false, 'reason', 'forfeited', 'last_seq', m.last_seq);
  end if;

  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, effective_seat, me, k,
          case when k = 'forfeit' then coalesce(p_move, '{}'::jsonb) || jsonb_build_object('seat', effective_seat)
               else coalesce(p_move, '{}'::jsonb) end,
          p_hash);

  update nx_matches
     set last_seq = p_seq,
         state_hash = coalesce(p_hash, state_hash),
         turn_seat = effective_seat,
         turn_deadline = now() + interval '45 seconds'
   where id = p_match;

  -- a player who left through the move log: when one seat is left the match ends for everyone
  if k = 'forfeit' then
    select coalesce(array_agg(g), '{}'::int[]) into alive
      from generate_series(0, n - 1) g where not (g = any(gone)) and g <> effective_seat;
    if coalesce(array_length(alive, 1), 0) = 1 then
      perform nx_finish_match_as(p_match, alive, effective_seat);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'seq', p_seq);
end;
$$;
revoke all on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) to authenticated, service_role;

-- ------------------------------------------------------------------------------------------------ 6-7. consensus finish
-- Same rules as 20261121000000_g_pro_result_integrity, plus: a player still sending the match heartbeat is never
-- "gone", and quick rooms close after the match instead of returning to a full lobby.
create or replace function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text default null::text, p_reason text default 'finished'::text)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  me uuid := auth.uid();
  m nx_matches;
  n int;
  w int[];
  forfeited int[];
  required uuid[];
  missing uuid[];
  n_reports int;
  n_winner_sets int;
  n_hashes int;
  n_null_hash int;
  final_scores int[];
  k int;
  u uuid;
  gone boolean := true;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  if me is null or not (me = any(m.players)) then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', true, 'already', true, 'winners', m.winner_seats, 'status', m.status);
  end if;
  n := coalesce(array_length(m.players, 1), 0);

  if exists (select 1 from unnest(coalesce(p_winners, '{}'::int[])) x where x is null or x < 0 or x >= n) then
    return jsonb_build_object('ok', false, 'error', 'bad_winners');
  end if;
  select coalesce(array_agg(distinct x order by x), '{}'::int[]) into w from unnest(coalesce(p_winners, '{}'::int[])) x;

  insert into nx_match_reports(match_id, user_id, winners, scores, state_hash, reason)
  values (p_match, me, w, p_scores, nullif(left(p_hash, 128), ''), left(coalesce(p_reason, 'finished'), 40))
  on conflict (match_id, user_id) do nothing;

  forfeited := public._nx_forfeited_seats(p_match);
  select coalesce(array_agg(m.players[g]), '{}'::uuid[]) into required
    from generate_series(1, n) g
   where m.players[g] is not null and not ((g - 1) = any(forfeited));
  select coalesce(array_agg(x), '{}'::uuid[]) into missing
    from unnest(required) x
   where not exists (select 1 from nx_match_reports r where r.match_id = p_match and r.user_id = x);

  select count(*), count(distinct winners), count(distinct state_hash), count(*) filter (where state_hash is null)
    into n_reports, n_winner_sets, n_hashes, n_null_hash
    from nx_match_reports where match_id = p_match;

  if n_winner_sets > 1 or (n_null_hash = 0 and n_hashes > 1) then
    update nx_matches set status = 'disputed', winner_seats = null, reason = 'disputed', ended_at = now()
     where id = p_match;
    perform _nx_room_after_match(m.room_id, m.id);
    return jsonb_build_object('ok', true, 'disputed', true, 'winners', null);
  end if;

  if coalesce(array_length(missing, 1), 0) > 0 then
    if now() <= m.turn_deadline or m.started_at > now() - interval '30 seconds' then
      gone := false;
    else
      foreach u in array missing loop
        if public._nx_player_active(p_match, u, 30, 30)
           or exists (select 1 from nx_room_players rp where rp.room_id = m.room_id and rp.user_id = u
                    and rp.last_seen > now() - interval '30 seconds') then
          gone := false;
          exit;
        end if;
      end loop;
    end if;
    if not gone then
      return jsonb_build_object('ok', true, 'pending', true, 'reports', n_reports,
                                'needed', coalesce(array_length(required, 1), 0));
    end if;
  end if;

  select r.winners into w from nx_match_reports r where r.match_id = p_match limit 1;
  final_scores := null;
  if not exists (select 1 from nx_match_reports r where r.match_id = p_match and r.scores is null) then
    final_scores := '{}'::int[];
    for k in 1..n loop
      final_scores := final_scores || (select min(r.scores[k]) from nx_match_reports r where r.match_id = p_match);
    end loop;
  end if;
  update nx_matches set status = 'finished', winner_seats = w, scores = final_scores,
         reason = left(coalesce(p_reason, 'finished'), 40),
         state_hash = coalesce((select max(r.state_hash) from nx_match_reports r where r.match_id = p_match), state_hash),
         ended_at = now()
   where id = p_match returning * into m;
  perform _nx_apply_result(m, w, final_scores);
  perform _nx_room_after_match(m.room_id, m.id);
  return jsonb_build_object('ok', true, 'winners', w);
end $function$;
revoke all on function public.nx_finish_match(uuid, integer[], integer[], text, text) from public, anon, authenticated;
grant execute on function public.nx_finish_match(uuid, integer[], integer[], text, text) to authenticated, service_role;
