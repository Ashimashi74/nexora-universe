-- Games project (eyzafhrefnqlwcjpcdyg): snapshot of functions that are live but were not tracked in this folder
-- (or whose live definition is newer than the last repo copy): nx_join_room (rooms v6 unified join through
-- nx_room_join), nx_game_bounds (stickman_arena / ludo_battle seat bounds), the quiz engine, nx_g_push,
-- nx_room_member_role, the physics-contract and result-guard helpers. Taken verbatim from pg_get_functiondef on
-- 2026-11-23, so applying it to the live project changes nothing; a fresh project gets the same code.
-- Grants mirror the live ACLs (no revokes, so re-running is a no-op).

CREATE OR REPLACE FUNCTION public._nx_g_turn_times(p_game text, OUT aim_s integer, OUT sim_s integer)
 RETURNS record
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_game when 'billiards' then 30 when 'carrom' then 15 else 10 end,
         case p_game when 'billiards' then 25 when 'carrom' then 12 else 5 end
$function$;

grant execute on function public._nx_g_turn_times(text) to anon, authenticated, public, service_role;

CREATE OR REPLACE FUNCTION public._nx_quiz_const(OUT q_ms integer, OUT grace_ms integer, OUT reveal_ms integer, OUT lead_ms integer, OUT pick_s integer)
 RETURNS record
 LANGUAGE sql
 IMMUTABLE
AS $function$ select 15000, 1500, 4500, 2500, 20 $function$;

grant execute on function public._nx_quiz_const() to anon, authenticated, public, service_role;

CREATE OR REPLACE FUNCTION public._nx_quiz_tick(p_match uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  g nx_quiz_games; m nx_matches; c record; active int[]; n_ans int; i int := 0;
  sc int[]; cc int[]; best int; bestc int; w int[]; s int;
begin
  select * into c from _nx_quiz_const();
  select * into m from nx_matches where id = p_match;
  select * into g from nx_quiz_games where match_id = p_match for update;
  if g.match_id is null then return; end if;
  if m.status <> 'playing' and g.phase <> 'done' then
    update nx_quiz_games set phase = 'done', phase_ends = null where match_id = p_match;
    return;
  end if;
  active := array(select x from generate_series(0, array_length(m.players, 1) - 1) x
                  where not (x = any(_nx_forfeited_seats(p_match))));
  while i < 4 loop
    i := i + 1;
    if g.phase = 'question' then
      select count(*) into n_ans from nx_quiz_answers a where a.match_id = p_match and a.round = g.round_idx
         and a.seat = any(active);
      exit when now() < g.phase_ends and n_ans < coalesce(array_length(active, 1), 0);
      update nx_quiz_games set phase = 'reveal', phase_started = now(),
             phase_ends = now() + make_interval(secs => c.reveal_ms / 1000.0)
       where match_id = p_match returning * into g;
    elsif g.phase = 'reveal' then
      exit when now() < g.phase_ends;
      if g.round_idx >= coalesce(array_length(g.qids, 1), 0) - 1 then
        -- final result
        n_ans := array_length(m.players, 1);
        sc := array(select coalesce((select sum(points) from nx_quiz_answers a where a.match_id = p_match and a.seat = x), 0)::int
                      from generate_series(0, n_ans - 1) x order by x);
        cc := array(select (select count(*) from nx_quiz_answers a where a.match_id = p_match and a.seat = x and a.correct)::int
                      from generate_series(0, n_ans - 1) x order by x);
        best := -1; bestc := -1; w := '{}';
        foreach s in array active loop
          if sc[s + 1] > best or (sc[s + 1] = best and cc[s + 1] > bestc) then
            best := sc[s + 1]; bestc := cc[s + 1]; w := array[s];
          elsif sc[s + 1] = best and cc[s + 1] = bestc then
            w := w || s;
          end if;
        end loop;
        if best <= 0 or (coalesce(array_length(active, 1), 0) > 1 and coalesce(array_length(w, 1), 0) = coalesce(array_length(active, 1), 0)) then w := '{}'; end if; -- draw
        update nx_quiz_games set phase = 'done', phase_ends = null, winners = w where match_id = p_match returning * into g;
        perform set_config('nx.server_result', '1', true);
        perform nx_finish_match(p_match, w, sc, null, 'finished');
        perform set_config('nx.server_result', '', true);
        exit;
      end if;
      update nx_quiz_games set phase = 'question', round_idx = g.round_idx + 1,
             phase_started = now() + interval '600 milliseconds',
             phase_ends = now() + interval '600 milliseconds' + make_interval(secs => (c.q_ms + c.grace_ms) / 1000.0)
       where match_id = p_match returning * into g;
    else
      exit;
    end if;
  end loop;
end $function$;

grant execute on function public._nx_quiz_tick(uuid) to service_role;

CREATE OR REPLACE FUNCTION public._nx_server_result_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.game in ('quiz', 'mafia') and old.status = 'playing' and new.status = 'finished'
     and coalesce(new.reason, 'finished') not like 'forfeit%'
     and coalesce(current_setting('nx.server_result', true), '') <> '1' then
    raise exception 'the server decides % results', new.game;
  end if;
  return new;
end $function$;

grant execute on function public._nx_server_result_guard() to anon, authenticated, public, service_role;

CREATE OR REPLACE FUNCTION public.nx_apply_physics_contract()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c nx_physics_contracts;
begin select * into c from public.nx_physics_contracts where game = new.game; if found then new.physics_version := c.version; new.physics_contract := c.contract; end if; return new; end; $function$;

grant execute on function public.nx_apply_physics_contract() to service_role;

CREATE OR REPLACE FUNCTION public.nx_g_push(p_match uuid, p_seq integer, p_kind text, p_move jsonb, p_hash text, p_seat integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  m nx_matches;
  caller_seat int;
  seat int;
  n int;
  k text := left(coalesce(p_kind, 'move'), 16);
  t record;
  cur int;
  dl timestamptz;
  nt int;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  if m.game not in ('carrom', 'billiards') then raise exception 'nx_g_push is for carrom/billiards'; end if;
  caller_seat := array_position(m.players, me) - 1;
  if caller_seat is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', false, 'reason', 'over', 'last_seq', m.last_seq);
  end if;
  if p_seq <> m.last_seq + 1 then
    return jsonb_build_object('ok', false, 'reason', 'seq', 'last_seq', m.last_seq);
  end if;
  if p_seat is not null and p_seat <> caller_seat and k not in ('snap', 'timeout', 'system') then
    raise exception 'seat mismatch';
  end if;
  seat := coalesce(p_seat, caller_seat);
  n := greatest(1, coalesce(array_length(m.players, 1), 1));
  select * into t from _nx_g_turn_times(m.game);
  cur := m.turn_seat;
  dl := m.turn_deadline;
  if m.last_seq = 0 then
    if m.game = 'billiards' then cur := (m.seed % 2)::int; end if;
    dl := greatest(dl, m.started_at + interval '60 seconds');
  end if;

  if k = 'move' then
    if seat <> cur then
      return jsonb_build_object('ok', false, 'reason', 'turn', 'turn_seat', cur);
    end if;
    if now() > dl + interval '2 seconds' then
      return jsonb_build_object('ok', false, 'reason', 'timeout', 'turn_seat', cur);
    end if;
    if coalesce(p_move->>'a', '') = 'shot' then
      dl := now() + make_interval(secs => t.sim_s + t.aim_s + 4);
    end if;
  elsif k = 'timeout' then
    if seat <> cur then
      return jsonb_build_object('ok', false, 'reason', 'turn', 'turn_seat', cur);
    end if;
    if now() < dl - interval '5 seconds' then
      return jsonb_build_object('ok', false, 'reason', 'too_early', 'turn_seat', cur);
    end if;
    cur := (cur + 1) % n;
    dl := now() + make_interval(secs => t.aim_s + 4);
  elsif k = 'snap' then
    nt := nullif(p_move->>'nt', '')::int;
    if nt is not null and nt >= 0 and nt < n then
      cur := nt;
      dl := now() + make_interval(secs => t.aim_s + 4);
    end if;
  elsif k not in ('system', 'forfeit') then
    raise exception 'bad kind';
  end if;

  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, seat, me, k, coalesce(p_move, '{}'::jsonb), p_hash);
  update nx_matches
     set last_seq = p_seq, state_hash = coalesce(p_hash, state_hash), turn_seat = cur, turn_deadline = dl
   where id = p_match;
  return jsonb_build_object('ok', true, 'seq', p_seq, 'turn_seat', cur);
end;
$function$;

grant execute on function public.nx_g_push(uuid,integer,text,jsonb,text,integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_game_bounds(p_game text, OUT min_seats integer, OUT max_seats integer)
 RETURNS record
 LANGUAGE sql
 IMMUTABLE
AS $function$
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
           when 'stickman_arena' then 4
           when 'ludo_battle' then 4
           else 2 end
$function$;

grant execute on function public.nx_game_bounds(text) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_join_room(p_code text DEFAULT NULL::text, p_room uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare me uuid:=auth.uid(); rid uuid; r nx_rooms; joined jsonb; seat_no int; begin if me is null then raise exception 'not signed in'; end if; if p_room is not null then rid:=p_room; else select id into rid from nx_rooms where code=upper(trim(p_code)); end if; if rid is null then raise exception 'room not found'; end if; select * into r from nx_rooms where id=rid for update; joined:=nx_room_join(rid,'speaker'); seat_no:=nullif(joined->>'seat','')::int; if seat_no is not null and not exists(select 1 from nx_room_players where room_id=rid and user_id=me) then insert into nx_room_players(room_id,user_id,seat,ready) values(rid,me,seat_no,false) on conflict(room_id,user_id) do update set last_seen=now(); end if; update nx_room_members set last_seen=now() where room_id=rid and user_id=me; return jsonb_build_object('room_id',rid,'code',r.code,'seat',seat_no,'role',joined->>'role','status',r.status,'match_id',r.match_id,'rejoined',coalesce((joined->>'rejoined')::boolean,false)); end $function$;

grant execute on function public.nx_join_room(text,uuid) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_quiz_answer(p_match uuid, p_round integer, p_choice integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); m nx_matches; g nx_quiz_games; v_seat int; c record; q nx_quiz_questions;
  e int; ok boolean; pts int; n int;
begin
  select * into c from _nx_quiz_const();
  select * into m from nx_matches where id = p_match;
  if m.id is null or m.game <> 'quiz' then raise exception 'not a quiz match'; end if;
  v_seat := array_position(m.players, me) - 1;
  if v_seat is null then raise exception 'not a player'; end if;
  if v_seat = any(_nx_forfeited_seats(p_match)) then return jsonb_build_object('ok', false, 'reason', 'left'); end if;
  if p_choice is null or p_choice < 0 or p_choice > 3 then return jsonb_build_object('ok', false, 'reason', 'choice'); end if;
  select * into g from nx_quiz_games where match_id = p_match;
  if g.match_id is null or g.phase <> 'question' or g.round_idx <> p_round then
    return jsonb_build_object('ok', false, 'reason', 'round');
  end if;
  if now() < g.phase_started then return jsonb_build_object('ok', false, 'reason', 'early'); end if;
  if now() > g.phase_ends then return jsonb_build_object('ok', false, 'reason', 'late'); end if;
  select * into q from nx_quiz_questions where id = g.qids[g.round_idx + 1];
  e := least(c.q_ms, greatest(0, (extract(epoch from (now() - g.phase_started)) * 1000)::int));
  ok := p_choice = q.correct and e < c.q_ms;
  pts := case when ok then 100 + round(50.0 * (c.q_ms - e) / c.q_ms)::int else 0 end;
  insert into nx_quiz_answers(match_id, round, seat, user_id, choice, elapsed_ms, correct, points)
  values (p_match, p_round, v_seat, me, p_choice, e, ok, pts)
  on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'reason', 'already'); end if;
  perform _nx_quiz_tick(p_match);
  return jsonb_build_object('ok', true, 'round', p_round);
end $function$;

grant execute on function public.nx_quiz_answer(uuid,integer,integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_quiz_start(p_match uuid, p_category text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); m nx_matches; g nx_quiz_games; v_seat int; cat text; c record; ids text[]; need int;
begin
  select * into c from _nx_quiz_const();
  select * into m from nx_matches where id = p_match;
  if m.id is null or m.game <> 'quiz' then raise exception 'not a quiz match'; end if;
  v_seat := array_position(m.players, me) - 1;
  if v_seat is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then return nx_quiz_state(p_match); end if;
  insert into nx_quiz_games(match_id) values (p_match) on conflict do nothing;
  select * into g from nx_quiz_games where match_id = p_match for update;
  if g.phase <> 'pick' then return nx_quiz_state(p_match); end if;
  if v_seat <> 0 and now() < m.started_at + make_interval(secs => c.pick_s) then
    raise exception 'the host picks the category';
  end if;
  cat := nullif(nullif(lower(coalesce(p_category, '')), ''), 'mixed');
  if cat is not null and not exists (select 1 from nx_quiz_questions where category = cat and active) then cat := null; end if;
  need := g.rounds;
  -- least-seen first (by anyone in this match), then random; fill from other categories if needed
  ids := array(
    select q.id from nx_quiz_questions q
     where q.active
     order by (case when cat is null or q.category = cat then 0 else 1 end),
              (select count(*) from nx_quiz_seen s where s.question_id = q.id and s.user_id = any(m.players)),
              random()
     limit need);
  insert into nx_quiz_seen(user_id, question_id)
  select u, qid from unnest(m.players) u cross join unnest(ids) qid
  on conflict (user_id, question_id) do update set seen_at = now();
  update nx_quiz_games set category = cat, qids = ids, round_idx = 0, phase = 'question',
         phase_started = now() + make_interval(secs => c.lead_ms / 1000.0),
         phase_ends = now() + make_interval(secs => (c.lead_ms + c.q_ms + c.grace_ms) / 1000.0)
   where match_id = p_match;
  return nx_quiz_state(p_match);
end $function$;

grant execute on function public.nx_quiz_start(uuid,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_quiz_state(p_match uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid(); m nx_matches; g nx_quiz_games; v_seat int; c record; q nx_quiz_questions;
  n int; active int[]; due boolean := false; res jsonb; answered int[]; mine jsonb; reveal jsonb;
  sc int[]; cc int[];
begin
  select * into c from _nx_quiz_const();
  select * into m from nx_matches where id = p_match;
  if m.id is null or m.game <> 'quiz' then raise exception 'not a quiz match'; end if;
  v_seat := array_position(m.players, me) - 1;
  if v_seat is null then raise exception 'not a player'; end if;
  insert into nx_quiz_games(match_id) values (p_match) on conflict do nothing;
  select * into g from nx_quiz_games where match_id = p_match;
  n := array_length(m.players, 1);
  active := array(select x from generate_series(0, n - 1) x where not (x = any(_nx_forfeited_seats(p_match))));
  if g.phase in ('question', 'reveal') and now() >= g.phase_ends then due := true; end if;
  if g.phase = 'question' and not due then
    due := (select count(*) from nx_quiz_answers a where a.match_id = p_match and a.round = g.round_idx and a.seat = any(active))
           >= coalesce(array_length(active, 1), 0);
  end if;
  if (g.phase <> 'done' and m.status <> 'playing') then due := true; end if;
  if due then
    perform _nx_quiz_tick(p_match);
    select * into g from nx_quiz_games where match_id = p_match;
    select * into m from nx_matches where id = p_match;
  end if;
  sc := array(select coalesce((select sum(points) from nx_quiz_answers a where a.match_id = p_match and a.seat = x
                                  and (a.round < g.round_idx or g.phase in ('reveal', 'done'))), 0)::int
                from generate_series(0, n - 1) x order by x);
  cc := array(select (select count(*) from nx_quiz_answers a where a.match_id = p_match and a.seat = x and a.correct
                         and (a.round < g.round_idx or g.phase in ('reveal', 'done')))::int
                from generate_series(0, n - 1) x order by x);
  res := jsonb_build_object(
    'phase', g.phase, 'round', g.round_idx, 'rounds', coalesce(array_length(g.qids, 1), g.rounds),
    'category', coalesce(g.category, 'mixed'), 'seat', v_seat, 'players', n,
    'names', to_jsonb(m.names), 'active', to_jsonb(active),
    'scores', to_jsonb(sc), 'correct_counts', to_jsonb(cc),
    'starts_in_ms', greatest(0, (extract(epoch from (g.phase_started - now())) * 1000)::int),
    'ends_in_ms', case when g.phase_ends is null then null
                       else greatest(0, (extract(epoch from (g.phase_ends - now())) * 1000)::int) end,
    'elapsed_ms', greatest(0, (extract(epoch from (now() - g.phase_started)) * 1000)::int),
    'time_limit_ms', c.q_ms, 'status', m.status, 'winners', to_jsonb(coalesce(g.winners, m.winner_seats)),
    'pick_wait_ms', greatest(0, (extract(epoch from (m.started_at + make_interval(secs => c.pick_s) - now())) * 1000)::int));
  if g.phase in ('question', 'reveal') and g.round_idx >= 0 then
    select * into q from nx_quiz_questions where id = g.qids[g.round_idx + 1];
    res := res || jsonb_build_object('question', jsonb_build_object(
      'id', q.id, 'category', q.category, 'difficulty', q.difficulty, 'fa', q.fa, 'en', q.en,
      'options_fa', q.options_fa, 'options_en', q.options_en));
    answered := array(select a.seat from nx_quiz_answers a where a.match_id = p_match and a.round = g.round_idx order by a.seat);
    res := res || jsonb_build_object('answered', to_jsonb(answered));
    select jsonb_build_object('choice', a.choice, 'ms', a.elapsed_ms) into mine
      from nx_quiz_answers a where a.match_id = p_match and a.round = g.round_idx and a.seat = v_seat;
    res := res || jsonb_build_object('mine', mine);
    if g.phase = 'reveal' then
      select jsonb_agg(jsonb_build_object('seat', a.seat, 'choice', a.choice, 'correct', a.correct,
                                          'points', a.points, 'ms', a.elapsed_ms) order by a.seat)
        into reveal from nx_quiz_answers a where a.match_id = p_match and a.round = g.round_idx;
      res := res || jsonb_build_object('correct', q.correct, 'answers', coalesce(reveal, '[]'::jsonb));
    end if;
  end if;
  return res;
end $function$;

grant execute on function public.nx_quiz_state(uuid) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.nx_room_member_role(p_room uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select role from public.nx_room_members where room_id=p_room and user_id=auth.uid() $function$;

grant execute on function public.nx_room_member_role(uuid) to anon, authenticated, public, service_role;
