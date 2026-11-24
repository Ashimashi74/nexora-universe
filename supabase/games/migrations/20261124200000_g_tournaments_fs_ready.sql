-- NEXORA GAMES project (eyzafhrefnqlwcjpcdyg) · tournaments: finger-soccer launch fixes (2026-11-24).
-- Idempotent: only CREATE OR REPLACE FUNCTION. Applied live 2026-11-24.
--
-- 1. nx_t_save: the server accepted only 5 games while the wizard offers 11 (kTournamentGames) -> 'bad_game' for the
--    arcade 1-vs-1 games. The allow-list now matches the client.
-- 2. nx_t_admin: a manual "Draw now" inside the check-in window (10 min before start) threw out every player who had not
--    checked in yet, even seconds after the window opened (this is what cancelled the "bermuda" tournament on 2026-11-20
--    as not_enough_players). A manual draw before the start time no longer purges; no-shows lose their first match by
--    walkover at the ready check. A manual "Start now" still removes non-checked-in players once the window is open.
-- 3. _nx_t_validate_cfg: max_game_minutes (after which a running game becomes a 'game_timeout' dispute) could be shorter
--    than the game itself (e.g. 7-minute games with a 5-minute cap -> every game disputed). Floor: match length + 10 min,
--    or 15 min for "first to N goals".

CREATE OR REPLACE FUNCTION public.nx_t_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; old nx_tournaments; isnew boolean; adm boolean; paid boolean;
        n_appr int; times_changed boolean := false; prize jsonb; dsum int := 0; v jsonb;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  adm := nx_t_is_admin(me);
  isnew := (p ->> 'id') is null;
  if isnew then
    if not nx_t_is_organizer(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    t.id := gen_random_uuid(); t.status := 'draft'; t.created_by := me; t.config := '{}'; t.prize := '{}';
    t.game := 'finger_soccer'; t.format := 'single_elim'; t.capacity := 16; t.min_players := 2; t.reg_mode := 'open';
    t.min_level := 0; t.min_xp := 0; t.min_rating := 0; t.fee_coins := 0; t.fee_gems := 0; t.seeding := 'random';
    t.description := ''; t.rules := ''; t.paused := false; t.stage := 'main'; t.escrow_coins := 0; t.escrow_gems := 0;
    t.paid_out := false; t.created_at := now();
  else
    select * into t from nx_tournaments where id = (p ->> 'id')::uuid for update;
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  end if;
  old := t;
  -- always editable
  if p ? 'title' then t.title := left(trim(p ->> 'title'), 80); end if;
  if p ? 'description' then t.description := left(coalesce(p ->> 'description', ''), 4000); end if;
  if p ? 'rules' then t.rules := left(coalesce(p ->> 'rules', ''), 4000); end if;
  if p ? 'reg_open_at' and t.status in ('draft', 'scheduled') then t.reg_open_at := (p ->> 'reg_open_at')::timestamptz; end if;
  if p ? 'reg_close_at' and t.status in ('draft', 'scheduled', 'registering') then t.reg_close_at := (p ->> 'reg_close_at')::timestamptz; end if;
  if p ? 'draw_at' and t.status in ('draft', 'scheduled', 'registering', 'closed') then t.draw_at := (p ->> 'draw_at')::timestamptz; end if;
  if p ? 'start_at' and t.status in ('draft', 'scheduled', 'registering', 'closed', 'drawn') then t.start_at := (p ->> 'start_at')::timestamptz; end if;
  if p ? 'config' then
    if t.status in ('draft', 'scheduled', 'registering', 'closed') then
      t.config := _nx_t_validate_cfg(p -> 'config');
    else
      -- after the draw only timing settings may change
      v := p -> 'config';
      t.config := _nx_t_validate_cfg(t.config || jsonb_strip_nulls(jsonb_build_object(
        'round_starts', v -> 'round_starts', 'round_minutes', v -> 'round_minutes', 'ready_seconds', v -> 'ready_seconds',
        'max_game_minutes', v -> 'max_game_minutes')));
    end if;
  end if;
  if t.status in ('draft', 'scheduled', 'registering', 'closed') then
    select count(*) into n_appr from nx_t_entries where tournament_id = t.id and status = 'approved';
    select exists (select 1 from nx_t_entries where tournament_id = t.id and (paid_coins > 0 or paid_gems > 0)) into paid;
    if p ? 'game' then t.game := p ->> 'game'; end if;
    if p ? 'format' then t.format := p ->> 'format'; end if;
    if p ? 'capacity' then t.capacity := greatest(n_appr, (p ->> 'capacity')::int); end if;
    if p ? 'min_players' then t.min_players := greatest(2, least((p ->> 'min_players')::int, t.capacity)); end if;
    if p ? 'reg_mode' then t.reg_mode := p ->> 'reg_mode'; end if;
    if p ? 'min_level' then t.min_level := greatest(0, (p ->> 'min_level')::int); end if;
    if p ? 'min_xp' then t.min_xp := greatest(0, (p ->> 'min_xp')::int); end if;
    if p ? 'min_rating' then t.min_rating := greatest(0, (p ->> 'min_rating')::int); end if;
    if p ? 'seeding' then t.seeding := p ->> 'seeding'; end if;
    if not paid then
      if p ? 'fee_coins' then t.fee_coins := greatest(0, (p ->> 'fee_coins')::int); end if;
      if p ? 'fee_gems' then t.fee_gems := greatest(0, (p ->> 'fee_gems')::int); end if;
    elsif (p ? 'fee_coins' and (p ->> 'fee_coins')::int <> t.fee_coins) or (p ? 'fee_gems' and (p ->> 'fee_gems')::int <> t.fee_gems) then
      return jsonb_build_object('ok', false, 'error', 'fee_locked');
    end if;
    if p ? 'prize' then
      prize := coalesce(p -> 'prize', '{}'::jsonb);
      prize := jsonb_build_object(
        'fixed_coins', greatest(0, _nx_t_cfg_int(prize, 'fixed_coins', 0)),
        'fixed_gems', greatest(0, _nx_t_cfg_int(prize, 'fixed_gems', 0)),
        'pool_pct', greatest(0, least(_nx_t_cfg_int(prize, 'pool_pct', 0), 100)),
        'fee_pct', greatest(0, least(_nx_t_cfg_int(prize, 'fee_pct', 0), 50)),
        'dist', case when jsonb_typeof(prize -> 'dist') = 'array' then prize -> 'dist' else '[60,30,10]'::jsonb end);
      select coalesce(sum(greatest(0, x::numeric::int)), 0) into dsum from jsonb_array_elements_text(prize -> 'dist') x;
      if dsum > 100 or jsonb_array_length(prize -> 'dist') > 64 then
        return jsonb_build_object('ok', false, 'error', 'bad_distribution'); end if;
      -- minting coins/gems out of nothing is an admin decision
      -- (admins, the owner and tournament admins with the 'unlimited' perk; nothing is deducted from their balance,
      --  every payout is still written to nx_t_ledger)
      if (_nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0)
          or _nx_t_cfg_int(prize, 'fixed_gems', 0) > _nx_t_cfg_int(old.prize, 'fixed_gems', 0)) then
        if not (adm or nx_unlimited(me)) then
          -- limited managers: gem prizes within their budget (set by the main admin); coin prizes stay admin-only
          if _nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0) then
            return jsonb_build_object('ok', false, 'error', 'fixed_prize_admin_only'); end if;
          if _nx_t_cfg_int(prize, 'fixed_gems', 0) > nx_t_gem_budget_left(me, t.id) then
            return jsonb_build_object('ok', false, 'error', 'gem_budget_exceeded',
                                      'left', nx_t_gem_budget_left(me, t.id)); end if;
        end if;
        perform _nx_t_audit(t.id, me, 'fixed_prize_minted', jsonb_build_object(
          'fixed_coins', _nx_t_cfg_int(prize, 'fixed_coins', 0), 'fixed_gems', _nx_t_cfg_int(prize, 'fixed_gems', 0),
          'by', case when adm then 'admin' when nx_unlimited(me) then 'manager_unlimited' else 'manager_budget' end));
      end if;
      t.prize := prize;
    end if;
  end if;
  if t.title is null or char_length(t.title) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if t.format not in ('single_elim', 'double_elim', 'two_legs', 'round_robin', 'groups_ko', 'swiss', 'custom') then
    return jsonb_build_object('ok', false, 'error', 'bad_format'); end if;
  if t.capacity is null or t.capacity < 2 or t.capacity > 64 then return jsonb_build_object('ok', false, 'error', 'bad_capacity'); end if;
  if t.game not in ('finger_soccer', 'carrom', 'billiards', 'backgammon', 'quiz', 'kart_racing', 'obstacle_race',
                    'bomb_arena', 'pool8', 'mini_golf', 'basketball_battle') then
    return jsonb_build_object('ok', false, 'error', 'bad_game'); end if;
  if t.reg_open_at is null or t.reg_close_at is null or t.draw_at is null or t.start_at is null
     or not (t.reg_open_at < t.reg_close_at and t.reg_close_at <= t.draw_at and t.draw_at <= t.start_at) then
    return jsonb_build_object('ok', false, 'error', 'bad_times'); end if;
  if t.format = 'groups_ko' and t.capacity < 4 then return jsonb_build_object('ok', false, 'error', 'groups_need_4'); end if;
  times_changed := not isnew and old.status <> 'draft' and (old.reg_open_at, old.reg_close_at, old.draw_at, old.start_at, old.config -> 'round_starts', old.config -> 'round_minutes')
                   is distinct from (t.reg_open_at, t.reg_close_at, t.draw_at, t.start_at, t.config -> 'round_starts', t.config -> 'round_minutes');
  t.updated_at := now();
  if isnew then
    insert into nx_tournaments select t.*;
    perform _nx_t_audit(t.id, me, 'created', jsonb_build_object('title', t.title, 'format', t.format));
  else
    update nx_tournaments set title = t.title, description = t.description, rules = t.rules, game = t.game, format = t.format,
           capacity = t.capacity, min_players = t.min_players, config = t.config, reg_mode = t.reg_mode, min_level = t.min_level,
           min_xp = t.min_xp, min_rating = t.min_rating, fee_coins = t.fee_coins, fee_gems = t.fee_gems, prize = t.prize,
           reg_open_at = t.reg_open_at, reg_close_at = t.reg_close_at, draw_at = t.draw_at, start_at = t.start_at,
           seeding = t.seeding, updated_at = now()
     where id = t.id;
    perform _nx_t_audit(t.id, me, 'edited', jsonb_build_object('times_changed', times_changed));
  end if;
  if times_changed then
    perform _nx_t_sync_jobs(t.id);
    perform _nx_t_reschedule(t.id);
    perform _nx_t_notify_all(t.id, 'time_changed', jsonb_build_object('start_at', t.start_at, 'reg_close_at', t.reg_close_at,
              'draw_at', t.draw_at), 'time:' || t.id || ':' || floor(extract(epoch from clock_timestamp()))::bigint,
              array['approved', 'pending', 'waitlist']);
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_admin(p_t uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  -- an early manual draw/start happens before anybody could check in: nobody is thrown out for not checking in
  -- check-in purge on a manual action: a manual "draw now" never throws out registered players (the check-in window
  -- may have opened seconds earlier, nobody could check in yet; no-shows lose their first match by walkover instead);
  -- a manual "start now" removes the players who did not check in only once the check-in window is open.
  perform set_config('nx.t_checkin_window',
                     case when p_action in ('draw', 'redraw') and now() < t.start_at then 'closed'
                          when now() >= t.start_at - interval '10 minutes' then 'open' else 'closed' end, true);
  case p_action
    when 'publish' then
      if t.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
      update nx_tournaments set status = case when reg_open_at <= now() then 'registering' else 'scheduled' end,
             published_at = now(), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'open_reg' then
      if t.status <> 'scheduled' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'registering', reg_open_at = least(reg_open_at, now()), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'close_reg' then
      if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'closed', reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             updated_at = now() where id = p_t;
      update nx_t_jobs set done_at = now() where idem_key = 'close_reg:' || p_t and done_at is null;
    when 'draw', 'redraw' then
      if p_action = 'redraw' then
        if t.status <> 'drawn' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
        delete from nx_t_matches where tournament_id = p_t;
        update nx_tournaments set status = 'closed', seed = null, stage = 'main' where id = p_t;
      elsif t.status not in ('registering', 'closed') then
        return jsonb_build_object('ok', false, 'error', 'bad_status');
      end if;
      update nx_tournaments set reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())) where id = p_t;
      perform _nx_t_draw(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t) and done_at is null;
    when 'start' then
      if t.status not in ('registering', 'closed', 'drawn') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set
             reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())),
             start_at = greatest(reg_open_at + interval '1 second', least(start_at, now())) where id = p_t;
      perform _nx_t_start(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t, 'start:' || p_t, 'remind_start:' || p_t)
         and done_at is null;
      perform _nx_t_reschedule(p_t);
    when 'pause' then
      update nx_tournaments set paused = true, updated_at = now() where id = p_t;
    when 'resume' then
      update nx_tournaments set paused = false, updated_at = now() where id = p_t;
      for r in select id from nx_t_matches where tournament_id = p_t and status = 'ready_check' loop
        update nx_t_matches set ready_deadline = now() + make_interval(secs => _nx_t_cfg_int(t.config, 'ready_seconds', 300))
         where id = r.id;
      end loop;
    when 'cancel' then
      perform _nx_t_cancel(p_t, coalesce(nullif(p_reason, ''), 'cancelled_by_organizer'), me);
    when 'finish' then
      if t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_t_matches set status = 'void', result_note = 'closed_by_organizer', updated_at = now()
       where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
      perform _nx_t_finish(p_t);
    when 'delete' then
      if t.status <> 'draft' or exists (select 1 from nx_t_ledger where tournament_id = p_t) then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_tournaments where id = p_t;
      return jsonb_build_object('ok', true, 'deleted', true);
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(p_t, me, 'admin_' || p_action, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'status', (select status from nx_tournaments where id = p_t));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_validate_cfg(c jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare o jsonb := coalesce(c, '{}'::jsonb); k text;
begin
  foreach k in array array['bo_early', 'bo_semi', 'bo_final'] loop
    if _nx_t_cfg_int(o, k, 1) not between 1 and 15 then o := o || jsonb_build_object(k, 1); end if;
  end loop;
  -- online match length: 3 / 5 / 7 minutes, or first to N goals (0 = game default)
  if _nx_t_cfg_int(o, 'match_minutes', 0) not in (0, 3, 5, 7) then o := o || '{"match_minutes": 5}'::jsonb; end if;
  o := o || jsonb_build_object('goal_target', greatest(0, least(_nx_t_cfg_int(o, 'goal_target', 0), 20)),
                               'checkin', _nx_t_cfg_bool(o, 'checkin', true));
  if _nx_t_cfg_int(o, 'goal_target', 0) > 0 then o := o || '{"match_minutes": 0}'::jsonb; end if;
  o := o || jsonb_build_object(
    'groups', greatest(1, least(_nx_t_cfg_int(o, 'groups', 2), 16)),
    'advance', greatest(1, least(_nx_t_cfg_int(o, 'advance', 2), 8)),
    'swiss_rounds', greatest(0, least(_nx_t_cfg_int(o, 'swiss_rounds', 0), 12)),
    'points_win', greatest(0, least(_nx_t_cfg_int(o, 'points_win', 3), 10)),
    'points_draw', greatest(0, least(_nx_t_cfg_int(o, 'points_draw', 1), 10)),
    'ready_seconds', greatest(30, least(_nx_t_cfg_int(o, 'ready_seconds', 300), 3600)),
    'round_minutes', greatest(1, least(_nx_t_cfg_int(o, 'round_minutes', 20), 10080)),
    'max_game_minutes', greatest(5, least(_nx_t_cfg_int(o, 'max_game_minutes', 30), 240)));
  -- a game is only declared stuck ("game_timeout" dispute) well after its own clock could have run out:
  -- at least the match length + 10 minutes (lineup, 60 s reconnect grace, golden goal), or 15 minutes for "first to N goals"
  o := o || jsonb_build_object('max_game_minutes', greatest(_nx_t_cfg_int(o, 'max_game_minutes', 30),
    case when _nx_t_cfg_int(o, 'goal_target', 0) > 0 then 15
         else (case when _nx_t_cfg_int(o, 'match_minutes', 0) in (3, 5, 7) then _nx_t_cfg_int(o, 'match_minutes', 0) else 5 end) + 10 end));
  return o;
end $function$;
