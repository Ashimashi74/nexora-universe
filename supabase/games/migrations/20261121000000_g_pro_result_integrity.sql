-- ANIX PRO · match result integrity (games project). Forward-only; idempotent; never drops data.
--
-- 1. nx_finish_match no longer lets one phone dictate the result. Every caller's report is stored in
--    nx_match_reports; the match is finalized (status 'finished' + _nx_apply_result) only when
--      a) every required player (all players minus forfeited seats) has reported and all reports agree on the winners
--         (and on state_hash when every report carries one), or
--      b) the players that have not reported are gone: the turn clock has lapsed (now() > turn_deadline), they
--         posted no move in the last 30 s, their lobby heartbeat is older than 30 s, and the match is older than 30 s.
--    Otherwise it returns {ok:true, pending:true}. Conflicting reports mark the match 'disputed' (no rewards).
--    Return shape stays compatible: {ok, winners} on finalize, {ok, already, winners} after the end.
-- 2. _nx_apply_result: fixed +16/-12 replaced by Elo (K = 32, expected score from nx_game_stats.rating, default 1000;
--    with more than two players each player is rated against the average rating of the opponents). Everything else in
--    the function is unchanged.
-- 3. Grants mirror the existing style.

-- ------------------------------------------------------------------------------------------------ status
alter table public.nx_matches drop constraint if exists nx_matches_status_check;
do $$ begin
  alter table public.nx_matches add constraint nx_matches_status_check
    check (status = any (array['playing'::text, 'finished'::text, 'abandoned'::text, 'disputed'::text]));
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------------------------------------------ reports
create table if not exists public.nx_match_reports (
  match_id uuid not null,
  user_id uuid not null,
  winners int[] not null default '{}',
  scores int[],
  state_hash text,
  reason text,
  created_at timestamptz not null default now(),
  primary key (match_id, user_id)
);
create index if not exists nx_match_reports_created on public.nx_match_reports(created_at);
alter table public.nx_match_reports enable row level security;
-- no policies: clients have no direct access; only the SECURITY DEFINER RPCs touch it.
revoke all on table public.nx_match_reports from public, anon, authenticated;
grant all on table public.nx_match_reports to service_role;

-- ------------------------------------------------------------------------------------------------ Elo
CREATE OR REPLACE FUNCTION public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i int; j int; uid uuid; oc text; sc int; v_xp int; v_co int; rd int; n int := array_length(m.players, 1);
        ratings int[] := '{}'; opp_sum numeric; opp_avg numeric; expected numeric; actual numeric;
begin
  -- ratings before this match (default 1000)
  for i in 1..n loop
    ratings := ratings || coalesce((select s.rating from nx_game_stats s where s.user_id = m.players[i] and s.game = m.game), 1000);
  end loop;
  for i in 1..n loop
    uid := m.players[i];
    if p_winners is null or array_length(p_winners, 1) is null then oc := 'draw';
    elsif (i - 1) = any(p_winners) then oc := case when array_length(p_winners, 1) = n then 'draw' else 'win' end;
    else oc := 'loss'; end if;
    sc := coalesce(p_scores[i], 0);
    -- Elo, K = 32, vs the average opponent rating
    if n > 1 then
      opp_sum := 0;
      for j in 1..n loop
        if j <> i then opp_sum := opp_sum + ratings[j]; end if;
      end loop;
      opp_avg := opp_sum / (n - 1);
      expected := 1.0 / (1.0 + power(10.0, (opp_avg - ratings[i]) / 400.0));
      actual := case oc when 'win' then 1.0 when 'loss' then 0.0 else 0.5 end;
      rd := round(32 * (actual - expected))::int;
    else
      rd := 0;
    end if;
    insert into nx_match_results(match_id, user_id, game, seat, outcome, score, rating_delta)
    values (m.id, uid, m.game, i - 1, oc, sc, rd) on conflict do nothing;
    if found then
      insert into nx_game_stats(user_id, game, played, won, lost, draw, rating, best)
      values (uid, m.game, 1, (oc = 'win')::int, (oc = 'loss')::int, (oc = 'draw')::int, greatest(0, 1000 + rd), sc)
      on conflict (user_id, game) do update set
        played = nx_game_stats.played + 1,
        won = nx_game_stats.won + (excluded.won),
        lost = nx_game_stats.lost + (excluded.lost),
        draw = nx_game_stats.draw + (excluded.draw),
        rating = greatest(0, nx_game_stats.rating + rd),
        best = greatest(nx_game_stats.best, excluded.best),
        updated_at = now();
      v_xp := case oc when 'win' then 80 when 'draw' then 40 else 20 end;
      v_co := case oc when 'win' then 50 when 'draw' then 20 else 8 end;
      insert into nx_xp_events(user_id, idem_key, event, xp, coins)
      values (uid, 'match:' || m.id::text, 'online.' || m.game || '.' || oc, v_xp, v_co) on conflict do nothing;
      if found then
        update profiles p set xp = p.xp + v_xp, coins = p.coins + v_co, level = level_for_xp(p.xp + v_xp) where p.id = uid;
      end if;
    end if;
  end loop;
end $function$;

-- ------------------------------------------------------------------------------------------------ consensus finish
CREATE OR REPLACE FUNCTION public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text DEFAULT NULL::text, p_reason text DEFAULT 'finished'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- normalized winners: distinct, sorted, valid seats only
  if exists (select 1 from unnest(coalesce(p_winners, '{}'::int[])) x where x is null or x < 0 or x >= n) then
    return jsonb_build_object('ok', false, 'error', 'bad_winners');
  end if;
  select coalesce(array_agg(distinct x order by x), '{}'::int[]) into w from unnest(coalesce(p_winners, '{}'::int[])) x;

  -- first report per player is kept (a phone cannot change its claim)
  insert into nx_match_reports(match_id, user_id, winners, scores, state_hash, reason)
  values (p_match, me, w, p_scores, nullif(left(p_hash, 128), ''), left(coalesce(p_reason, 'finished'), 40))
  on conflict (match_id, user_id) do nothing;

  -- required reporters: every player whose seat has not forfeited
  select coalesce(array_agg(distinct coalesce((mv.move ->> 'seat')::int, mv.seat)), '{}'::int[]) into forfeited
    from nx_match_moves mv where mv.match_id = p_match and mv.kind = 'forfeit';
  select coalesce(array_agg(m.players[g]), '{}'::uuid[]) into required
    from generate_series(1, n) g
   where m.players[g] is not null and not ((g - 1) = any(forfeited));
  select coalesce(array_agg(x), '{}'::uuid[]) into missing
    from unnest(required) x
   where not exists (select 1 from nx_match_reports r where r.match_id = p_match and r.user_id = x);

  select count(*), count(distinct winners), count(distinct state_hash), count(*) filter (where state_hash is null)
    into n_reports, n_winner_sets, n_hashes, n_null_hash
    from nx_match_reports where match_id = p_match;

  -- conflicting claims -> disputed, no rewards
  if n_winner_sets > 1 or (n_null_hash = 0 and n_hashes > 1) then
    update nx_matches set status = 'disputed', winner_seats = null, reason = 'disputed', ended_at = now()
     where id = p_match;
    update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
    update nx_room_players set ready = false where room_id = m.room_id and seat > 0;
    return jsonb_build_object('ok', true, 'disputed', true, 'winners', null);
  end if;

  if coalesce(array_length(missing, 1), 0) > 0 then
    -- lone-survivor rule: everyone who has not reported must be gone
    if now() <= m.turn_deadline or m.started_at > now() - interval '30 seconds' then
      gone := false;
    else
      foreach u in array missing loop
        if exists (select 1 from nx_match_moves mv where mv.match_id = p_match and mv.by_user = u
                    and mv.created_at > now() - interval '30 seconds')
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

  -- finalize with the agreed winners; scores = element-wise minimum over the reports (conservative)
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
  update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
  update nx_room_players set ready = false where room_id = m.room_id and seat > 0;
  return jsonb_build_object('ok', true, 'winners', w);
end $function$;


-- ------------------------------------------------------------------------------------------------ host forfeit guard
-- The authority phone may still forfeit an ABSENT seat, but no longer a seat that already reported a result or that
-- posted a move in the last 30 seconds (otherwise the host could "forfeit" an opponent to dictate the result).
-- Body otherwise identical to g_games_core.
CREATE OR REPLACE FUNCTION public.nx_forfeit(p_match uuid, p_seat integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_matches; s int; others int[];
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null or m.status <> 'playing' then return jsonb_build_object('ok', false); end if;
  s := array_position(m.players, me) - 1;
  if s is null then raise exception 'not a player'; end if;
  if p_seat is not null and p_seat <> s then
    if s <> 0 then raise exception 'authority only'; end if;  -- host may forfeit an absent seat
    if p_seat < 0 or p_seat >= array_length(m.players, 1) then return jsonb_build_object('ok', false, 'reason', 'bad_seat'); end if;
    if exists (select 1 from nx_match_reports r where r.match_id = p_match and r.user_id = m.players[p_seat + 1]) then
      return jsonb_build_object('ok', false, 'reason', 'reported');
    end if;
    if exists (select 1 from nx_match_moves mv where mv.match_id = p_match and mv.by_user = m.players[p_seat + 1]
                and mv.created_at > now() - interval '30 seconds') then
      return jsonb_build_object('ok', false, 'reason', 'active');
    end if;
    s := p_seat;
  end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move)
  values (p_match, m.last_seq + 1, s, me, 'forfeit', jsonb_build_object('seat', s));
  update nx_matches set last_seq = m.last_seq + 1 where id = p_match;
  if array_length(m.players, 1) = 2 then
    select array_agg(g) into others from generate_series(0, 1) g where g <> s;
    return nx_finish_match_as(p_match, others, s);
  end if;
  return jsonb_build_object('ok', true, 'seat', s);
end $function$;

-- ------------------------------------------------------------------------------------------------ grants
revoke all on function public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[]) from public, anon, authenticated;
grant execute on function public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[]) to service_role;
revoke all on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) from public, anon, authenticated;
grant execute on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) to authenticated;
grant execute on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) to service_role;
revoke all on function public.nx_forfeit(p_match uuid, p_seat integer) from public, anon, authenticated;
grant execute on function public.nx_forfeit(p_match uuid, p_seat integer) to authenticated;
grant execute on function public.nx_forfeit(p_match uuid, p_seat integer) to service_role;
